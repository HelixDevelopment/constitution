"""ext_engine.py — implementation of the constitution extension engine.

Invoked only through scripts/constitution_ext/constitution_ext.sh (see that file for the user-facing
documentation, §11.4.18). Standard library only; the manifest parser is ext_yaml.py next to this file.
Design notes live in scripts/constitution_ext/README.md.

Security invariants (each has a test in tests/extensions/ and a paired mutation in test_mutations.sh):
  R1  no code from an extension is ever executed (copy only; git checkout with hooks disabled)
  R2  every path in a manifest and every tree entry is contained (no .., no absolute, no symlinks,
      no special files, no setuid/setgid, size/count/depth limits)
  R3  strict schema: unknown keys and duplicate keys rejected
  R4  pins: git sources need a 40-hex sha, local sources a sha256, unless --waiver-id is given
      (recorded in the lock); any mismatch is exit 5
  R5  consent (--yes or /dev/tty) recorded with the capability list; hooks/MCP disabled until enable
  R6  no secret-shaped values in manifests; env vars by NAME only; values never echoed
  R7  atomic staged install with journal + rollback; verify-after-install
  R8  recursive deletes only through scripts/lib/safe_rm.sh safe_rm_rf
  R9  catalog revocation honoured on add and verify
  R10 tools_bindings must resolve to an existing target
  R11 the wiring file is untrusted input: every entry is project-relative, must equal the shim path this
      engine would compute for (agent, root, command), live inside the project (resolved), and a link's
      text must be the relative path to the extension's own commands/<command>; otherwise every command
      that reads it refuses (no deletion)
  R12 the journal is untrusted input: final == _installed/<id>, aux == _installed/.trash-<pid>-<hex>;
      anything else is reported and ignored; recovery never deletes a tree the lock holds
  R13 one exclusive flock on the project directory (and the root's extensions/) for the WHOLE command
  R14 no embedded git metadata (a .git component at any depth, any case, or a HEAD+config+objects/
      bare-repository triple); no hardlinks; bounded file, directory and byte counts
  R15 git runs with a scrubbed environment (no inherited GIT_*, no system/global config, hooks off,
      symlinks off, filters/text conversion off via info/attributes, protocol allow-list); symlink and
      gitlink blobs in a git source are refused
  R16 source URLs carry no credentials (userinfo) and no secret-shaped text; the same rule binds
      catalog release URLs
  R17 a local, untracked, HMAC-protected state record per extension (consent, enabled, source, pins)
      is cross-checked against the tracked lock by verify, wire, enable and disable
  R18 state files are never written or read through a symlink (O_NOFOLLOW, lstat)
  R19 test seams (kill points, version override) are inert outside a test sandbox proven by a nonce
  R20 wiring provenance: a wiring entry may make the engine delete or overwrite a file only when it is in
      the local HMAC-signed wiring record (extensions.state/wiring.json) or the file itself carries the
      engine's managed-by marker for that id and command; an unbound entry makes wire/unwire/remove/
      disable refuse and verify fail (a forged entry can never delete a user's own file)
  R21 agent-side execution: command and skill bodies that contain agent shell injection (!{...}, !`...`,
      allowed-tools or hooks front-matter keys, found by parsing the one accepted front-matter form) or
      file injection (@{...}, and ANY '@' at a token start followed by a non-space: @path, @mention,
      @decorator; only an in-word '@' such as an e-mail address is not one) must be declared in
      capabilities.agent_shell / capabilities.reads_files;
      undeclared constructs refuse add/enable/wire. Every file an agent can reach (all of commands/<name>/,
      symlinked dirs included, and skill paths) is scanned; a file that cannot be read as UTF-8 text, an
      unreadable directory, or front matter in any other form is a refusal, never a pass (fail closed).
      The rendered gemini/qwen shim is scanned again after rendering (M2)
  R22 MCP launch commands: an ALLOW-LIST (round 6). Unless capabilities.shell lists the server, a launch
      mapping may carry only the keys in MCP_KEYS (any launcher-like key such as run/script/argv/exec is
      refused) and may start (a) a regular file inside the extension (relative path with a '/') or (b) an
      allow-listed interpreter (python3, node, ruby, perl) with allow-listed options only and a regular
      in-tree file as first operand; arguments are plain tokens, env NAMES must be listed in the server's
      env_vars and not code-bearing, cwd must be a directory inside the extension, envFile needs shell
      consent. Secret-looking keys or values anywhere in MCP/hook/config JSON refuse like manifests; argv is
      shown redacted. For extensions with hooks, MCP servers or executables the consent carries the digest of
      the whole tree (tree-sha256:), so a change to any file a launch can load needs fresh consent
  I2 claude shims link to a snapshot of the command directory under extensions.snapshots/<id>/<cmd>/<sha>,
      made from and compared with exactly the content wire checked; a later change of the live tree reaches
      the agent only through a new wire; verify flags a changed snapshot and an old-format live link
  I3 read-only commands never recover or delete; garbage collection never runs beside an invalid journal;
      a trash directory is deleted only through the journal that names it
  M1 every byte printed passes one sink that escapes control, bidi and other non-printing characters
  M3 a lock that refreshed only part of the entries says so; M4 files are opened O_NOFOLLOW|O_NONBLOCK and
      checked to be regular after opening; M5 deeply nested JSON is a reasoned refusal, never a crash
"""
import hmac
import unicodedata
import urllib.parse
import fcntl
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import ext_yaml  # noqa: E402

_BAD_CATS = frozenset(("Cc", "Cf", "Zl", "Zp", "Cs", "Co"))


def bad_chars(s):
    """True iff S contains a control (C0/C1), format (bidi overrides, zero-width), separator, surrogate
    or private-use character. Such characters are refused in every checked string."""
    return any(unicodedata.category(c) in _BAD_CATS for c in s)


def disp(s):
    """Escape characters that could reorder or hide text on a terminal (for display only)."""
    s = str(s)
    return "".join(("\\u%04x" % ord(c)) if unicodedata.category(c) in _BAD_CATS else c for c in s)

EXIT_OK, EXIT_FAIL, EXIT_USAGE, EXIT_REFUSED, EXIT_VERIFY = 0, 1, 2, 3, 5

ID_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,62}\Z")
NAME_RE = ID_RE
WAIVER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")
SHA40_RE = re.compile(r"[0-9a-f]{40}\Z")
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
ENV_RE = re.compile(r"[A-Z_][A-Z0-9_]{0,127}\Z")
TOOL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}\Z")
HOST_RE = re.compile(r"(\*\.)?[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?\Z")
ANCHOR_RE = re.compile(r"[0-9]+(\.[0-9]+){1,4}\Z")
TAG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,31}\Z")
# numeric identifiers are capped at 9 digits and a version at MAX_VERSION_LEN characters, so int()
# never sees a huge digit string (Python's int-from-str digit limit would otherwise raise)
SEMVER_RE = re.compile(
    r"(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})"
    r"(?:-((?:0|[1-9]\d{0,8}|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d{0,8}|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?\Z")
CONSTRAINT_RE = re.compile(r"\s*(>=|<=|==|>|<)\s*([0-9]{1,9}(?:\.[0-9]{1,9}){0,3})(?:[-+][0-9A-Za-z.-]{1,40})?\s*\Z")
MAX_VERSION_LEN = 64

PLATFORMS = {"claude", "opencode", "gemini", "qwen", "pi", "kimi", "codex", "cursor", "aider", "copilot", "generic"}
STATUSES = {"SUPPORTED", "UNTESTED", "UNSUPPORTED", "CONFIG-ONLY"}
TRUST = {"builtin", "vetted", "community"}
_PHASES = ("specify", "plan", "tasks", "implement", "analyze", "checklist", "clarify", "constitution", "taskstoissues")
HOOK_EVENTS = {"session_start", "session_end", "pre_tool_use", "post_tool_use", "user_prompt_submit", "stop"} | \
    {p + x for p in ("before_", "after_") for x in _PHASES}
WIRE_AGENTS = ("claude", "opencode", "gemini", "qwen", "pi")

MAX_FILES = 2000
MAX_FILE_BYTES = 5 * 1024 * 1024
MAX_TREE_BYTES = 20 * 1024 * 1024
MAX_TREE_DEPTH = 12
MAX_DIRS = 2000
NAME_OK_RE = re.compile(r"[A-Za-z0-9._@+ -]{1,255}\Z")
CHECKSUMS = "CHECKSUMS.sha256"
MARKER = "managed-by: constitution_ext"
STATE_LIMITS = {"max_bytes": 64 * 1024 * 1024, "max_lines": 2000000, "max_nodes": 4000000}


class EngineError(Exception):
    def __init__(self, code, msg):
        Exception.__init__(self, msg)
        self.code = code
        self.msg = msg


# ── pure helpers (unit-tested) ─────────────────────────────────────────────────────────────
def is_semver(v):
    return isinstance(v, str) and len(v) <= MAX_VERSION_LEN and SEMVER_RE.match(v) is not None


def _vtuple(s):
    core = re.split(r"[-+]", s, maxsplit=1)[0]
    return tuple(int(x) for x in core.split("."))


def version_satisfies(version, constraint):
    """True iff VERSION satisfies every comma-separated clause of CONSTRAINT (>=,<=,==,>,<)."""
    if not isinstance(constraint, str) or len(constraint) > 200 or not is_semver(version) and \
            not re.fullmatch(r"[0-9]{1,9}(\.[0-9]{1,9}){0,3}", version or ""):
        raise ValueError("unsupported version or constraint")
    v = _vtuple(version)
    for clause in constraint.split(","):
        m = CONSTRAINT_RE.match(clause)
        if not m:
            raise ValueError("unsupported version constraint clause: %r" % clause.strip())
        op, ref = m.group(1), _vtuple(m.group(2))
        n = max(len(v), len(ref))
        a, b = v + (0,) * (n - len(v)), ref + (0,) * (n - len(ref))
        ok = {">=": a >= b, "<=": a <= b, "==": a == b, ">": a > b, "<": a < b}[op]
        if not ok:
            return False
    return True


_SECRET_RES = [
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"glpat-[A-Za-z0-9_-]{16,}"),
    re.compile(r"(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])"),
    re.compile(r"xox[abprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"-----BEGIN"),
    re.compile(r"AIza[0-9A-Za-z_-]{30,}"),
    re.compile(r"(?i)bearer\s+[A-Za-z0-9._~+/-]{20,}"),
]
_RUN_RE = re.compile(r"[A-Za-z0-9_+=-]{32,}")


def looks_secret(s):
    """Heuristic: does string S look like a credential value? (hex digests are not secrets)."""
    if not isinstance(s, str):
        return False
    for r in _SECRET_RES:  # RULE:R6-secret-patterns
        if r.search(s):
            return True
    for run in _RUN_RE.findall(s):
        if re.fullmatch(r"[0-9a-fA-F]+", run):
            continue
        if re.search(r"[A-Z]", run) and re.search(r"[a-z]", run) and re.search(r"[0-9]", run):
            return True
    return False


def relpath_ok(p):
    """A manifest path: relative, no '..' or '.' segments, no backslash/control chars."""
    if not isinstance(p, str) or not p or len(p) > 255:
        return False
    if p.startswith("/") or p.startswith("~") or "\\" in p:  # RULE:R2-abs-path
        return False
    if bad_chars(p):  # RULE:R2-control-chars
        return False
    segs = p.split("/")
    if any(s in ("", ".", "..") for s in segs):  # RULE:R2-dotdot
        return False
    return True


# schema: ("map", {key: (required, spec)}) | ("list", spec, maxlen) | ("str", regex|None, maxlen)
#         | ("bool",) | ("int", lo, hi) | ("path",) | ("enum", set) | ("semver",) | ("constraint",)
#         | ("compat",)
def _S(n=500):
    return ("str", None, n)


_CMD = ("map", {"name": (True, ("str", NAME_RE, 63)), "description": (True, _S(500)),
                "argument_hint": (False, _S(200)), "file": (False, ("path",)),
                "aliases": (False, ("list", ("str", NAME_RE, 63), 10))})
SCHEMA = ("map", {
    "schema_version": (True, ("enum", {"1.0"})),
    "extension": (True, ("map", {
        "id": (True, ("str", ID_RE, 63)),
        "name": (True, _S(100)),
        "version": (True, ("semver",)),
        "description": (True, _S(500)),
        "author": (False, _S(200)),
        "repository": (False, _S(300)),
        "license": (False, _S(64)),
        "homepage": (False, _S(300)),
        "source": (False, ("map", {"git": (True, _S(300)), "sha": (False, ("str", SHA40_RE, 40)),
                                   "sha256": (False, ("str", SHA256_RE, 64))})),
        "trust_tier": (False, ("enum", TRUST)),
    })),
    "requires": (False, ("map", {
        "constitution_version": (False, ("constraint",)),
        "extensions": (False, ("list", ("map", {"id": (True, ("str", ID_RE, 63)),
                                                "version": (False, ("constraint",))}), 50)),
        "tools": (False, ("list", ("map", {"name": (True, ("str", TOOL_RE, 64)),
                                           "required": (False, ("bool",)),
                                           "version": (False, _S(64))}), 50)),
        "anchors": (False, ("list", ("str", ANCHOR_RE, 32), 100)),
    })),
    "provides": (False, ("map", {
        "commands": (False, ("list", _CMD, 100)),
        "skills": (False, ("list", ("map", {"name": (True, ("str", NAME_RE, 63)), "path": (True, ("path",))}), 100)),
        "mcp": (False, ("list", ("map", {
            "name": (True, ("str", NAME_RE, 63)), "file": (True, ("path",)),
            "transport": (False, ("enum", {"stdio", "http"})), "command": (False, _S(255)),
            "args": (False, ("list", _S(255), 50)),
            "env_vars": (False, ("list", ("str", ENV_RE, 128), 50)),
            "network": (False, ("list", ("str", HOST_RE, 260), 50))}), 20)),
        "hooks": (False, ("list", ("map", {
            "event": (True, ("enum", HOOK_EVENTS)), "command": (True, ("path",)),
            "optional": (False, ("bool",)), "description": (False, _S(300)),
            "timeout_s": (False, ("int", 1, 600))}), 50)),
        "templates": (False, ("list", ("map", {"name": (True, ("str", NAME_RE, 63)), "file": (True, ("path",)),
                                               "target": (True, ("path",))}), 100)),
        "tools_bindings": (False, ("list", ("map", {
            "name": (True, ("str", NAME_RE, 63)), "kind": (True, ("enum", {"constitution-path", "command"})),
            "target": (True, _S(255)), "description": (False, _S(300))}), 50)),
        "config": (False, ("list", ("map", {"name": (True, ("str", NAME_RE, 63)), "template": (False, ("path",)),
                                            "description": (False, _S(300)), "required": (False, ("bool",))}), 50)),
    })),
    "capabilities": (False, ("map", {
        "writes": (False, ("list", ("path",), 50)),
        "network": (False, ("list", ("str", HOST_RE, 260), 50)),
        "executes": (False, ("list", ("path",), 50)),
        "reads_secrets": (False, ("bool",)),
        "agent_shell": (False, ("list", ("str", NAME_RE, 63), 100)),
        "reads_files": (False, ("list", ("str", NAME_RE, 63), 100)),
        "shell": (False, ("list", ("str", NAME_RE, 63), 20)),
    })),
    "compatibility": (False, ("compat",)),
    "tags": (False, ("list", ("str", TAG_RE, 32), 20)),
})
_COMPAT_ENTRY = ("map", {"status": (True, ("enum", STATUSES)), "min_version": (False, _S(64)),
                         "evidence": (False, ("path",))})


def _check(v, spec, where, errs):
    kind = spec[0]
    if kind == "map":
        if not isinstance(v, dict):
            errs.append("%s: must be a mapping" % where)
            return
        fields = spec[1]
        for k in sorted(v):
            if k not in fields:  # RULE:R3-unknown-key
                errs.append("%s: unknown key %r" % (where, k))
        for k, (req, sub) in sorted(fields.items()):
            if k in v and v[k] is not None:
                _check(v[k], sub, "%s.%s" % (where, k) if where else k, errs)
            elif req:
                errs.append("%s: required key %r missing" % (where or "<top>", k))
    elif kind == "list":
        if not isinstance(v, list):
            errs.append("%s: must be a list" % where)
            return
        if len(v) > spec[2]:
            errs.append("%s: more than %d items" % (where, spec[2]))
        for i, x in enumerate(v):
            _check(x, spec[1], "%s[%d]" % (where, i), errs)
    elif kind == "str":
        if not isinstance(v, str):
            errs.append("%s: must be a string" % where)
        elif len(v) > spec[2] or (spec[1] is not None and not spec[1].match(v)):
            errs.append("%s: invalid value (rule: %s, max %d chars)" % (where, spec[1].pattern if spec[1] else "text", spec[2]))
        elif bad_chars(v):  # RULE:R3-bad-chars
            errs.append("%s: control, bidi/format or separator characters are not allowed" % where)
    elif kind == "bool":
        if not isinstance(v, bool):
            errs.append("%s: must be true or false" % where)
    elif kind == "int":
        if not isinstance(v, int) or isinstance(v, bool) or not spec[1] <= v <= spec[2]:
            errs.append("%s: must be an integer in [%d, %d]" % (where, spec[1], spec[2]))
    elif kind == "path":
        if not relpath_ok(v):
            errs.append("%s: path must be relative and contained (no '..', no absolute, no '~')" % where)
    elif kind == "enum":
        if v not in spec[1]:
            errs.append("%s: must be one of %s" % (where, ", ".join(sorted(spec[1]))))
    elif kind == "semver":
        if not is_semver(v):
            errs.append("%s: must be a strict semantic version MAJOR.MINOR.PATCH" % where)
    elif kind == "constraint":
        try:
            if not isinstance(v, str):
                raise ValueError("not a string")
            version_satisfies("0.0.0", v)
        except ValueError:
            errs.append("%s: invalid version constraint (use >=X,<Y)" % where)
    elif kind == "compat":
        if not isinstance(v, dict):
            errs.append("%s: must be a mapping" % where)
            return
        for p in sorted(v):
            if p not in PLATFORMS:
                errs.append("%s: unknown platform %r" % (where, p))
                continue
            _check(v[p], _COMPAT_ENTRY, "%s.%s" % (where, p), errs)
            if isinstance(v[p], dict) and v[p].get("status") == "SUPPORTED" and not v[p].get("evidence"):
                errs.append("%s.%s: SUPPORTED requires an evidence path (§11.4.228)" % (where, p))


def _walk_strings(v, where, out):
    if isinstance(v, dict):
        for k in sorted(v):
            _walk_strings(v[k], "%s.%s" % (where, k) if where else k, out)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            _walk_strings(x, "%s[%d]" % (where, i), out)
    elif isinstance(v, str):
        out.append((where, v))


def validate_manifest(m):
    """Returns a sorted-stable list of error strings (empty = valid). Values are never echoed."""
    errs = []
    if not isinstance(m, dict):
        return ["<top>: manifest must be a mapping"]
    _check(m, SCHEMA, "", errs)
    strs = []
    _walk_strings(m, "", strs)
    for where, s in strs:
        if looks_secret(s):  # RULE:R6-secret-scan
            errs.append("%s: secret-looking value (value withheld; reference env var NAMES only)" % where)
    prov = m.get("provides") if isinstance(m.get("provides"), dict) else {}
    cmds = prov.get("commands") if isinstance(prov.get("commands"), list) else []
    names = [c.get("name") for c in cmds if isinstance(c, dict)]
    if len(names) != len(set(names)):
        errs.append("provides.commands: duplicate command names")
    ext = m.get("extension") if isinstance(m.get("extension"), dict) else {}
    if ext.get("trust_tier") not in (None, "community"):  # RULE:R3-trust-tier
        errs.append("extension.trust_tier: assigned by the engine or a catalog; a manifest may only declare community")
    for i, c in enumerate(cmds):
        if isinstance(c, dict) and c.get("file") is not None and isinstance(c.get("name"), str) \
                and c.get("file") != "commands/%s/SKILL.md" % c["name"]:
            errs.append("provides.commands[%d].file: must be commands/<name>/SKILL.md" % i)
    return errs


def check_tree(root, skip_git=False):
    """Containment and file-type checks over an extension tree. Returns a list of problems.
    SKIP_GIT skips ONLY a top-level .git (used by `validate` on an author's working checkout); a .git
    component anywhere else, in any letter case, is always refused, as is a bare-repository triple."""
    errs = []
    state = {"files": 0, "bytes": 0, "dirs": 0}

    def walk(d, rel, depth):
        if depth > MAX_TREE_DEPTH:
            errs.append("%s: directory nesting deeper than %d" % (rel or ".", MAX_TREE_DEPTH))
            return
        state["dirs"] += 1
        if state["dirs"] > MAX_DIRS:  # RULE:R14-dir-count
            if state["dirs"] == MAX_DIRS + 1:
                errs.append("tree has more than %d directories" % MAX_DIRS)
            return
        try:
            ents = sorted(os.scandir(d), key=lambda e: e.name)
        except OSError as ex:
            errs.append("%s: unreadable (%s)" % (rel or ".", ex.strerror))
            return
        low = {e.name.lower(): e for e in ents}
        if "head" in low and "config" in low and "objects" in low:  # RULE:R14-bare-repo
            errs.append("%s: looks like a git repository (HEAD, config, objects/); not allowed" % (rel or "."))
        for e in ents:
            r = (rel + "/" + e.name) if rel else e.name
            if skip_git and not rel and e.name == ".git":
                continue
            if e.name.lower() == ".git":  # RULE:R14-dotgit
                errs.append("%s: embedded git metadata (.git) is not allowed in an extension" % r)
                continue
            if not NAME_OK_RE.match(e.name) or e.name.startswith("-"):
                errs.append("%r: file name contains disallowed characters" % r)
                continue
            st = os.lstat(e.path)
            if stat.S_ISLNK(st.st_mode):  # RULE:R2-symlink
                errs.append("%s: symlinks are not allowed in an extension" % r)
            elif stat.S_ISDIR(st.st_mode):
                walk(e.path, r, depth + 1)
            elif stat.S_ISREG(st.st_mode):
                if st.st_mode & (stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):  # RULE:R2-setuid
                    errs.append("%s: setuid/setgid/sticky bits are not allowed" % r)
                if st.st_nlink > 1:  # RULE:R14-hardlink
                    errs.append("%s: hard-linked files are not allowed (link count %d)" % (r, st.st_nlink))
                if st.st_size > MAX_FILE_BYTES:  # RULE:R2-file-size
                    errs.append("%s: file larger than %d bytes" % (r, MAX_FILE_BYTES))
                state["files"] += 1
                state["bytes"] += st.st_size
            else:  # RULE:R2-special
                errs.append("%s: special files (fifo/socket/device) are not allowed" % r)
    walk(root, "", 0)
    if state["files"] > MAX_FILES:
        errs.append("tree has more than %d files" % MAX_FILES)
    if state["bytes"] > MAX_TREE_BYTES:
        errs.append("tree larger than %d bytes" % MAX_TREE_BYTES)
    return errs


def file_hashes(root, skip_git=False, keep_checksums=False):
    """{relpath: sha256} for every regular file except the top-level CHECKSUMS file (unless KEEP_CHECKSUMS)."""
    out = {}
    for dp, dns, fns in os.walk(root, onerror=_walk_error):
        rel = os.path.relpath(dp, root)
        if skip_git and rel == ".":
            dns[:] = [d for d in dns if d != ".git"]
        dns.sort()
        for n in sorted(fns):
            p = os.path.join(dp, n)
            r = n if rel == "." else rel + "/" + n
            if r == CHECKSUMS and not keep_checksums:
                continue
            st = os.lstat(p)
            if not stat.S_ISREG(st.st_mode):
                continue
            out[r] = _sha_file(p)
    return out


def digest_of_hashes(hashes):
    """The tree digest of a {relpath: sha256} mapping (what tree_digest returns for the tree it was read from)."""
    return hashlib.sha256(checksums_text(hashes).encode()).hexdigest()


def command_digest_of(hashes, prefix):
    """command_digest of the command directory whose files are the entries of HASHES below PREFIX
    ('commands/<name>/'): the digest the snapshot of that command must have, derived from the locked tree's
    per-file hashes and not from any stored value (I2)."""
    lines = ["%s\0%s\n" % (r[len(prefix):], h) for r, h in hashes.items() if r.startswith(prefix)]
    return hashlib.sha256("".join(sorted(lines)).encode("utf-8", "surrogateescape")).hexdigest()

def checksums_text(hashes):
    return "".join("%s  %s\n" % (hashes[r], r) for r in sorted(hashes, key=lambda x: x.encode()))


def tree_digest(root, skip_git=False):
    return hashlib.sha256(checksums_text(file_hashes(root, skip_git)).encode()).hexdigest()


def parse_checksums(text):
    out = {}
    for ln in text.splitlines():
        if not ln.strip():
            continue
        m = re.match(r"([0-9a-f]{64})  (.+)\Z", ln)
        if not m or m.group(2) in out:
            raise EngineError(EXIT_VERIFY, "%s: malformed line" % CHECKSUMS)
        out[m.group(2)] = m.group(1)
    return out


def capabilities_of(m, tree=None, skip_git=False):
    """The consent list. With TREE, the launch commands inside each MCP file, the sha256 of every bound file
    (bound_files) and, for an extension that has hooks, MCP servers or executables, the digest of the WHOLE tree
    (anything a hook, server or program can load) are part of it, so a changed hook body, MCP command, server
    script or exposed shell command no longer matches the recorded consent (I2, I3). Arguments are shown
    redacted (a secret-looking one is replaced, URL credentials and query values are masked)."""
    caps = set()
    c = m.get("capabilities") or {}
    for w in c.get("writes") or []:
        caps.add("writes:" + w)
    for h in c.get("network") or []:
        caps.add("network:" + h)
    for x in c.get("executes") or []:
        caps.add("executes:" + x)
    if c.get("reads_secrets"):
        caps.add("reads_secrets")
    for n in c.get("agent_shell") or []:
        caps.add("agent-shell:" + n)
    for n in c.get("reads_files") or []:
        caps.add("reads-files:" + n)
    for n in c.get("shell") or []:
        caps.add("shell:" + n)
    p = m.get("provides") or {}
    for h in p.get("hooks") or []:
        caps.add("hook:%s:%s" % (h["event"], h["command"]))
    for s in p.get("mcp") or []:
        caps.add("mcp:" + s["name"])
        for n in s.get("network") or []:
            caps.add("network:" + n)
        for ev in s.get("env_vars") or []:
            caps.add("env:" + ev)
            if not env_inert(ev):
                caps.add("env-code:" + ev)
        if s.get("command") is not None:
            caps.add("mcp-command:%s=%s" % (s["name"], _argv_text(s["command"], s.get("args"))))
        if tree is not None:
            doc = None
            try:
                doc = mcp_document(tree, s["file"])
                launchers = _json_launchers(doc, "", [])
            except (ValueError, EngineError):
                caps.add("mcp-file:%s=unreadable" % s["file"])
                launchers = []
            if len(launchers) > MAX_LAUNCHERS:  # the file is refused by mcp_problems; keep the list bounded
                caps.add("mcp-file:%s=too-many-launchers" % s["file"])
                launchers = launchers[:MAX_LAUNCHERS]
            servers = doc.get("mcpServers") if isinstance(doc, dict) else None
            for key in sorted(servers, key=str)[:MAX_LAUNCHERS] if isinstance(servers, dict) else []:
                caps.add("mcp-server:%s/%s" % (s["name"], _redact_item(key)))
                ent = servers[key]
                if isinstance(ent, dict) and "command" not in ent:
                    caps.add("mcp-endpoint:%s/%s=%s" % (s["name"], _redact_item(key), _redact_item(ent.get("url"))))
                    if isinstance(ent.get("headers"), dict):
                        for hk in sorted(ent["headers"], key=str)[:MAX_LAUNCHERS]:
                            caps.add("mcp-header:%s/%s.%s" % (s["name"], _redact_item(key), _redact_item(hk)))
            for where, d in launchers:
                caps.add("mcp-command:%s/%s=%s" % (s["name"], where, _argv_text(d.get("command"), d.get("args"))))
                if isinstance(d.get("env"), dict):
                    for k in sorted(d["env"], key=str)[:MAX_LAUNCHERS]:
                        caps.add("env:%s" % _redact_item(k))
                        if not env_inert(k):
                            caps.add("env-code:%s" % _redact_item(k))
                for k in sorted(d, key=str):  # cwd / environment file: shown at consent (R22)
                    if _knorm(k) in _DIR_NORM:
                        caps.add("mcp-dir:%s/%s.%s=%s" % (s["name"], where, _redact_item(k), _redact_item(d[k])))
    for b in p.get("tools_bindings") or []:
        caps.add("tool:%s:%s" % (b["kind"], b["target"]))
    for cmd in p.get("commands") or []:
        caps.add("command:" + cmd["name"])
    if tree is not None:
        try:
            rels = bound_files(tree, m)
        except EngineError:
            rels = ["<unreadable directory>"]
        for r in rels:
            caps.add("sha256:%s=%s" % (r, _sha_or_unreadable(os.path.join(tree, r))))
        if p.get("hooks") or p.get("mcp") or c.get("executes"):  # RULE:I3-tree-digest
            try:
                caps.add("tree-sha256:" + tree_digest(tree, skip_git))
            except EngineError:
                caps.add("tree-sha256:unreadable")
    return sorted(caps)


def _redact_item(x):
    """One command / argument / key / value for display and for the consent list: never a secret-looking
    string, URL credentials and query values masked, bounded in length."""
    if not isinstance(x, str):
        return "<non-string>"
    if looks_secret(x):
        return "<redacted>"
    return redact(x)[:300]


def _argv_text(cmd, args):
    items = [_redact_item(cmd)] + [_redact_item(a) for a in (args if isinstance(args, list) else [])[:100]]
    return json.dumps(items, separators=(",", ":"))


# R21 agent-side execution constructs. Sources (repo docs only): Gemini CLI custom commands process
# file-content injection @{...} and shell injection !{...} (docs/research/action_prefix_system/RESEARCH.md
# §1.2, citing geminicli.com). The Claude Code / OpenCode forms !`cmd` and @path and the Claude
# `allowed-tools` front-matter key are NOT documented in this repository: UNCONFIRMED, detected anyway
# (refusing a false positive is the safe direction; the author declares the capability).
AGENT_SHELL_RES = (re.compile(r"!\{"), re.compile(r"!`"))
# File injection is a CLASS, not a list of path shapes: any '@' at the start of a token (not preceded by a
# word character, so e-mail addresses and in-word '@' are not matched) followed by a non-space character
# can name a file the agent reads (@.env, @id_rsa, @Makefile, `@x`, *@x*, >@x, @{...}). False positives
# (an @mention, a decorator) are refused in the safe direction: the author declares reads_files.
AGENT_FILES_RES = (re.compile(r"@\{"), re.compile(r"(?<!\w)@(?=\S)"))  # RULE:R21-at-token
# front-matter keys (compared lower-case with '-' and '_' removed) that let the agent run tools/commands
FM_SHELL_KEYS = frozenset(("allowedtools", "hooks"))
_FM_OPEN_MSG = ("front matter must open with an exact '---' line as the first line (no BOM, CR, leading blank "
                "line or trailing characters)")


def front_matter(text):
    """Split TEXT into (front matter mapping or None, body). Raises ValueError with the reason when the
    file starts like front matter but is not exactly the one accepted form: no byte-order mark, an opening
    '---' line as the very first line, an exact closing '---' line, no carriage return inside, and a block
    the strict YAML subset parses (no quoted or complex keys, no flow mappings). Anything ambiguous is a
    refusal, so a key can never hide from the scan behind a spelling the agent accepts (R21)."""
    if text.startswith("﻿"):
        raise ValueError("starts with a byte-order mark")
    if not text.lstrip(" \t\r\n").startswith("---"):
        return None, text
    if not text.startswith("---\n"):
        raise ValueError(_FM_OPEN_MSG)  # RULE:R21-fm-open
    lines = text[4:].split("\n")
    for i, ln in enumerate(lines):
        if ln == "---":
            block = "\n".join(lines[:i]) + "\n"
            if "\r" in block:
                raise ValueError("carriage return inside the front matter")
            try:
                fm = ext_yaml.parse(block) if block.strip() else {}
            except ext_yaml.YamlError as ex:
                raise ValueError("front matter is not in the accepted YAML subset (%s)" % ex)
            if not isinstance(fm, dict):
                raise ValueError("front matter must be a mapping")
            return fm, "\n".join(lines[i + 1:])
        if ln.startswith(("---", "...")):
            raise ValueError("front matter delimiter line with extra characters (%r)" % disp(ln[:20]))
    raise ValueError("unterminated front matter (no closing '---' line)")


def _fm_keys(v, out):
    if isinstance(v, dict):
        for k, x in v.items():
            out.add(re.sub(r"[-_]", "", str(k).lower()))
            _fm_keys(x, out)
    elif isinstance(v, list):
        for x in v:
            _fm_keys(x, out)
    return out


def agent_constructs(text):
    """{'shell', 'files'} subset found in a command/skill file TEXT (R21). Raises ValueError when the
    front matter cannot be analysed (see front_matter)."""
    found = set()
    if any(r.search(text) for r in AGENT_SHELL_RES):  # RULE:R21-shell
        found.add("shell")
    fm, _body = front_matter(text)
    if fm is not None and _fm_keys(fm, set()) & FM_SHELL_KEYS:  # RULE:R21-allowed-tools
        found.add("shell")
    if any(r.search(text) for r in AGENT_FILES_RES):  # RULE:R21-files
        found.add("files")
    return found


def _walk_error(ex):
    raise EngineError(EXIT_VERIFY, "%s: unreadable directory (%s)" % (disp(getattr(ex, "filename", "?")), ex.strerror))


def _exposed_files(tree, m):
    """[(owner name, relpath)] of every file the agent can see through a command or skill: every entry
    below commands/<name>/ (all of it is exposed by a Claude link) and each skill file. A non-regular
    entry or an unreadable directory is returned as (name, relpath) too; the scan refuses it."""
    prov = m.get("provides") or {}
    out = []
    for c in prov.get("commands") or []:
        base = "commands/%s" % c["name"]
        top = os.path.join(tree, base)
        if not os.path.isdir(top) or os.path.islink(top):
            out.append((c["name"], base + "/SKILL.md"))
            continue
        for dp, dns, fns in os.walk(top, onerror=_walk_error):
            dns.sort()
            rel = os.path.relpath(dp, tree)
            for n in sorted(fns) + [d for d in dns if os.path.islink(os.path.join(dp, d))]:
                out.append((c["name"], rel + "/" + n))
    for s in prov.get("skills") or []:
        out.append((s["name"], s["path"]))
    return out


def construct_problems(tree, m):
    """R21: every command/skill file using an agent-side construct must be declared, and every declared
    name must be a command or skill of this extension. A file that cannot be read, is not a regular file,
    is not UTF-8 or has front matter that cannot be analysed is a problem (fail closed: an unscannable
    file is never treated as clean). Returns a list of problems."""
    errs = []
    prov = m.get("provides") or {}
    caps = m.get("capabilities") or {}
    decl = {"shell": set(caps.get("agent_shell") or []), "files": set(caps.get("reads_files") or [])}
    names = {c["name"] for c in prov.get("commands") or []} | {s["name"] for s in prov.get("skills") or []}
    for key, cls in (("agent_shell", "shell"), ("reads_files", "files")):
        for n in sorted(decl[cls] - names):
            errs.append("capabilities.%s: %s is not a command or skill of this extension" % (key, n))
    try:
        files = _exposed_files(tree, m)
    except EngineError as ex:
        return errs + [ex.msg]
    for name, rel in files:
        errs += file_construct_problems(rel, os.path.join(tree, rel), name, decl)
    return errs


def file_construct_problems(rel, path, name, decl):
    """R21 for ONE file the agent can reach (label REL, real path PATH) of the command or skill NAME; DECL is
    {'shell': set(names), 'files': set(names)}. Used on the extension tree, on the staged copy wire works from
    and on every snapshot verify re-checks."""
    errs = []
    try:
        text = _read_nofollow(path, MAX_FILE_BYTES, rel)
        found = agent_constructs(text)
    except EngineError as ex:  # RULE:R21-unreadable
        return ["%s cannot be scanned (%s); files exposed to an agent must be UTF-8 text" % (rel, ex.msg)]
    except ValueError as ex:
        return ["%s: %s" % (rel, ex)]
    for cls in sorted(found):
        if name not in decl[cls]:  # RULE:R21-declared
            what = ("agent shell execution (!{...}, !`...` or allowed-tools/hooks front matter)" if cls == "shell"
                    else "agent file injection (@{...} or @path)")
            errs.append("%s uses %s but capabilities.%s does not list %s" % (
                rel, what, "agent_shell" if cls == "shell" else "reads_files", name))
    return errs


def decl_of(m):
    caps = m.get("capabilities") or {}
    return {"shell": set(caps.get("agent_shell") or []), "files": set(caps.get("reads_files") or [])}


# R22 MCP launch commands: an ALLOW-LIST (review round 6; the deny-lists of rounds 3-5 were bypassed again on
# every review, so the question is inverted: what MAY an extension start, not what may it not).
# Unless capabilities.shell lists the server, a launch mapping may carry only the keys in MCP_KEYS and may start
#   (a) a program that is a regular file INSIDE the extension (a relative path containing a '/'), or
#   (b) one of the ALLOWED_INTERPRETERS (bare name) with allow-listed options only and, as its first operand, a
#       regular file inside the extension;
# with plain-token arguments (no absolute or '..' operands), environment variable NAMES that the server lists in
# env_vars and that are not code-bearing, plain values, and a cwd that is a directory inside the extension.
# Everything else (shells, wrappers, runners, package managers, any other interpreter, inline code, URLs, bare
# PATH programs, absolute paths, envFile) is refused unless the server is listed in capabilities.shell, which is
# part of the consent. The program, its arguments and every in-tree file it can load are covered by the tree
# digest in the consent list (capabilities_of), so changing them needs a new consent.
MCP_KEYS = frozenset(("command", "args", "env", "cwd", "type", "transport", "description", "timeout", "disabled",
                      "name"))
_LAUNCH_NORM = frozenset(("command", "cmd", "exec", "executable", "program", "entrypoint", "bin", "binary",
                          "launcher", "runner", "run", "script", "shell", "commandline", "argv", "args",
                          "arguments", "params", "parameters"))
_DIR_NORM = frozenset(("cwd", "workdir", "workingdir", "workingdirectory", "envfile", "dotenv", "envfiles"))
MAX_LAUNCHERS = 64          # launch mappings per MCP file (a bigger file would overflow the state record limit)
MAX_ARGV_BYTES = 16384      # total command + argument bytes per MCP file
ALLOWED_INTERPRETERS = (
    (re.compile(r"python3?(?:\.[0-9]{1,2})?\Z"), frozenset(("-u", "-B", "-E", "-s", "-S", "-I", "-O", "-OO", "-q",
                                                            "-b", "-bb"))),
    (re.compile(r"node(?:js)?\Z"), frozenset(("--no-warnings", "--no-deprecation", "--enable-source-maps",
                                          "--trace-warnings"))),
    (re.compile(r"ruby\Z"), frozenset(("-w", "-W0", "-W1", "-W2"))),
    (re.compile(r"perl\Z"), frozenset(("-w", "-W", "-T"))),
)
# environment variable names that can make a program load or run other code, change its configuration,
# search paths or network endpoints (second layer: the allow-list on env_vars is the first)
CODE_ENV_RE = re.compile(r"(?:LD_|DYLD_)[A-Z0-9_]*|[A-Z0-9_]*_(?:OPTIONS|OPTS|FLAGS|STARTUP|PRELOAD|INIT)"
                         r"|PYTHON[A-Z0-9_]*|NODE_[A-Z0-9_]*|PERL5?(?:OPT|LIB|DB)|RUBY(?:OPT|LIB)|GEM_(?:PATH|HOME)"
                         r"|LUA_(?:INIT|PATH|CPATH)[A-Z0-9_]*|CLASSPATH|BASH_ENV|ENV|ZDOTDIR|PROMPT_COMMAND"
                         r"|SHELLOPTS|BASHOPTS|IFS|PS4|PATH|EDITOR|VISUAL|PAGER|BROWSER|GIT_[A-Z0-9_]*|PHPRC"
                         r"|PHP_INI_SCAN_DIR|GCONV_PATH|ELECTRON_RUN_AS_NODE|TCLLIBPATH|R_PROFILE(?:_USER)?"
                         r"|R_ENVIRON(?:_USER)?|BUNDLE_GEMFILE|DENO_[A-Z0-9_]*|BUN_[A-Z0-9_]*"
                         r"|DOCKER_[A-Z0-9_]*|KUBE[A-Z0-9_]*|PODMAN_[A-Z0-9_]*|OPENSSL_[A-Z0-9_]*|GLIBC_[A-Z0-9_]*"
                         r"|SSL_[A-Z0-9_]*|TLS_[A-Z0-9_]*|AWS_(?:CONFIG|SHARED|CA)[A-Z0-9_]*"
                         r"|DOTNET_[A-Z0-9_]*|CORECLR_[A-Z0-9_]*|COR_[A-Z0-9_]*|LESSOPEN|LESSCLOSE|SSH_ASKPASS|ASKPASS"
                         r"|MANPAGER|GOFLAGS|GOPATH|GOPROXY|GOENV|PIP_[A-Z0-9_]*|UV_[A-Z0-9_]*|NPM_[A-Z0-9_]*"
                         r"|JULIA_[A-Z0-9_]*|HOME|USERPROFILE|XDG_[A-Z0-9_]*|TMPDIR|SHELL|LANG|LC_[A-Z0-9_]*"
                         r"|HTTPS?_PROXY|ALL_PROXY|NO_PROXY|SSL_CERT_[A-Z0-9_]*|REQUESTS_CA_BUNDLE|CURL_CA_BUNDLE"
                         r"|JAVA_[A-Z0-9_]*|JDK_[A-Z0-9_]*|MAVEN_[A-Z0-9_]*|GRADLE_[A-Z0-9_]*|CARGO_[A-Z0-9_]*"
                         r"|RUSTC[A-Z0-9_]*|RUSTUP_[A-Z0-9_]*|CONDA_[A-Z0-9_]*|VIRTUAL_ENV|MALLOC_[A-Z0-9_]*\Z")
# R22 environment names: an ALLOW-LIST of names that are inert by construction (credentials, endpoints, identifiers).
# A name must end in one of the suffixes below and must not be a loader / configuration-file / runtime-option name
# (CODE_ENV_RE, the minus-pattern). Every other name is refused unless the server is in capabilities.shell, and then
# it appears in the consent list as env-code:<NAME>. The class "what a program reads from its environment" is open
# (OPENSSL_CONF, KRB5_CONFIG, GLIBC_TUNABLES, ...), so it is never enumerated.
ENV_INERT_RE = re.compile(r"[A-Z][A-Z0-9_]*_(?:API_)?(?:KEY|TOKEN|URL|ENDPOINT|REGION|MODEL|ID|NAME|HOST|PORT|PROJECT"
                          r"|WORKSPACE)\Z")
ENV_URLISH_RE = re.compile(r"[A-Z][A-Z0-9_]*_(?:URL|ENDPOINT)\Z")
_ENV_URL_VALUE_RE = re.compile(r"https?://[A-Za-z0-9.-]{1,253}(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~%-]+)*/?\Z")
_ENV_PLAIN_VALUE_RE = re.compile(r"[A-Za-z0-9_.:,@+%=-]{0,255}\Z")
SAFE_ARG_RE = re.compile(r"[A-Za-z0-9_./:=,@+%-]{1,255}\Z")
_ENV_PLACEHOLDER_RE = re.compile(r"\$\{[A-Z_][A-Z0-9_]{0,127}\}\Z")
_SECRET_KEY_RE = re.compile(r"(?i)(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret|passw(?:or)?d|credential|"
                            r"private[_-]?key|authorization|(?:^|[_.-])token(?:$|[_.-])|[a-z]Token\Z|\Atoken\Z)")


def code_env(name):
    return isinstance(name, str) and bool(CODE_ENV_RE.fullmatch(name.upper()))


def env_inert(name):
    """True iff NAME is on the allow-list of inert environment variable names (R22)."""
    return isinstance(name, str) and bool(ENV_INERT_RE.fullmatch(name)) and not code_env(name)


def _knorm(k):
    return re.sub(r"[-_ .]", "", k.lower()) if isinstance(k, str) else ""


def _safe_key(k):
    """A JSON key for a message, a path or the consent list: a credential-shaped key is never echoed."""
    t = str(k)
    return "<redacted-key>" if looks_secret(t) or _SECRET_KEY_RE.search(t) and len(t) > 40 else disp(t)[:40]


def _launcher_like(d):
    return isinstance(d, dict) and any(_knorm(k) in _LAUNCH_NORM for k in d)


def _intree_file(tree, rel):
    """True iff REL is a normalised relative path naming a regular file below TREE, reached through real
    directories only (lstat: a symlink anywhere on the way is not accepted)."""
    return _intree(tree, rel, False)


def _intree(tree, rel, want_dir):
    if tree is None or not relpath_ok(rel):
        return False
    cur, segs = tree, rel.split("/")
    for n, seg in enumerate(segs):
        cur = os.path.join(cur, seg)
        try:
            mode = os.lstat(cur).st_mode
        except OSError:
            return False
        last = n == len(segs) - 1
        if not last and not stat.S_ISDIR(mode):
            return False
        if last and not (stat.S_ISDIR(mode) if want_dir else stat.S_ISREG(mode)):
            return False
    return True


def _plain_arg_problem(a):
    """Why argument A is not a plain token (None when it is): one token, no shell metacharacters, no '..',
    no absolute or home-relative operand (also in the value of an --option=value)."""
    if not SAFE_ARG_RE.match(a) or ".." in a.split("/"):
        return "is not a single plain token (whitespace, quotes, |&;$`<>(){}[]\\!*?~# and '..' are not allowed)"
    for part in a.split("="):  # RULE:R22-opt-value
        if part.startswith(("/", "~")) or ".." in part.split("/"):
            return "is an absolute or escaping path (operands must lie inside the extension)"
    return None


def _env_problems(where, env, env_vars):
    errs = []
    for k in sorted(env, key=str):
        v = env[k]
        if not isinstance(k, str) or not ENV_RE.match(k):
            errs.append("%s: environment variable name %s is not an upper-case NAME" % (where, _safe_key(k)))
        elif k not in (env_vars or ()):  # RULE:R22-env-allow
            errs.append("%s: environment variable %s is not listed in this server's env_vars; list the name in "
                        "provides.mcp[].env_vars, or list the server in capabilities.shell" % (where, _safe_key(k)))
        elif not env_inert(k):  # RULE:R22-code-env
            errs.append("%s: %s is not on the allow-list of inert environment names (a name ending in _KEY, _TOKEN, "
                        "_URL, _ENDPOINT, _REGION, _MODEL, _ID, _NAME, _HOST, _PORT, _PROJECT or _WORKSPACE); other "
                        "names can make a program load code or configuration; list the server in "
                        "capabilities.shell to declare it" % (where, _safe_key(k)))
        if not isinstance(v, str) or len(v) > 255 or not (v == "" or _ENV_PLACEHOLDER_RE.match(v)
                                                          or _env_value_ok(k, v)):  # RULE:R22-env-value
            errs.append("%s: the value of %s must be a ${NAME} reference or a plain token without a path separator "
                        "(only a *_URL / *_ENDPOINT name may hold an http(s) URL)" % (where, _safe_key(k)))
    return errs


def _env_value_ok(name, v):
    if isinstance(name, str) and ENV_URLISH_RE.fullmatch(name) and v.startswith(("http://", "https://")):
        return bool(_ENV_URL_VALUE_RE.match(v)) and ".." not in v.split("/")
    return bool(_ENV_PLAIN_VALUE_RE.match(v)) and "/" not in v and not v.startswith("~")


def mcp_command_problems(where, cmd, args, declared, env=None, tree=None, env_vars=None):
    """Problems with one MCP launch COMMAND + ARGS + ENV (R22, allow-list). DECLARED: capabilities.shell lists
    the server (then only the form of the command is checked). TREE is the extension directory; without it
    nothing can be proven to lie inside the extension, so only a declared server passes."""
    if not isinstance(cmd, str) or not cmd:
        return ["%s: command must be a non-empty string" % where]
    if args is None:
        args = []
    if not isinstance(args, list) or any(not isinstance(a, str) for a in args):
        return ["%s: args must be a list of strings" % where]
    if not (TOOL_RE.match(cmd) or relpath_ok(cmd)) or cmd.startswith("-"):  # RULE:R22-command-form
        return ["%s: command must be a bare program name or a relative path inside the extension "
                "(no absolute path, no '..')" % where]
    if declared:
        return []
    errs = []
    if "/" in cmd:
        if not _intree_file(tree, cmd):  # RULE:R22-intree-exec
            errs.append("%s: command %s is not a regular file inside the extension" % (where, disp(cmd)))
        else:
            for i, a in enumerate(args):
                why = _plain_arg_problem(a)
                if why:  # RULE:R22-args
                    errs.append("%s: args[%d] %s; list the server in capabilities.shell to declare it" % (where, i, why))
    else:
        opts = next((o for rx, o in ALLOWED_INTERPRETERS if rx.match(cmd)), None)
        if opts is None:  # RULE:R22-allow-list
            errs.append("%s: command %s is neither a program inside the extension nor an allow-listed interpreter "
                        "(python3, node, ruby, perl); list the server in capabilities.shell to declare it"
                        % (where, disp(cmd)))
        else:
            i = 0
            while i < len(args) and args[i].startswith("-"):
                if args[i] not in opts:  # RULE:R22-interp-option
                    errs.append("%s: option %s is not in the allow-list for %s; list the server in "
                                "capabilities.shell to declare it" % (where, disp(args[i][:40]), disp(cmd)))
                    break
                i += 1
            else:
                if i >= len(args) or not _intree_file(tree, args[i]):  # RULE:R22-interp-operand
                    errs.append("%s: the first operand of %s must be a script that is a regular file inside the "
                                "extension" % (where, disp(cmd)))
                else:
                    for j in range(i + 1, len(args)):
                        why = _plain_arg_problem(args[j])
                        if why:  # RULE:R22-args
                            errs.append("%s: args[%d] %s; list the server in capabilities.shell to declare it"
                                        % (where, j, why))
    if env:
        errs += _env_problems(where, env, env_vars)
    return errs


def mcp_launch_problems(where, d, declared, tree, env_vars):
    """R22 for one launch mapping D of an MCP file: key allow-list, cwd, then mcp_command_problems."""
    errs = []
    env = d.get("env")
    if env is not None and not isinstance(env, dict):
        errs.append("%s: env must be a mapping" % where)
        env = None
    for k in sorted(d, key=str):
        n = _knorm(k)
        if n in _DIR_NORM:
            v = d[k]
            if not relpath_ok(v):  # RULE:R22-dir-key
                errs.append("%s: %s must be a relative path inside the extension" % (where, _safe_key(k)))
            elif not declared and (n != "cwd" or not _intree(tree, v, True)):
                errs.append("%s: %s %s is not a directory inside the extension (an environment file needs the "
                            "server in capabilities.shell)" % (where, _safe_key(k), _safe_key(v)))
        elif not declared and k not in MCP_KEYS:  # RULE:R22-keys
            errs.append("%s: key %s is not allowed in a launch mapping (allowed: %s); list the server in "
                        "capabilities.shell to declare it" % (where, _safe_key(k), ", ".join(sorted(MCP_KEYS))))
    errs += mcp_command_problems(where, d.get("command"), d.get("args"), declared, env, tree, env_vars)
    return errs


def _json_launchers(v, path, out, depth=0):
    """Every launch-like mapping (any key naming a command or its arguments, any spelling) in a parsed MCP JSON
    document: [(where, mapping)]."""
    if depth > 64:
        raise ValueError("nested deeper than 64 levels")
    if isinstance(v, dict):
        if _launcher_like(v):
            out.append((path or "<top>", v))
        for k in sorted(v, key=str):
            _json_launchers(v[k], "%s.%s" % (path, _safe_key(k)) if path else _safe_key(k), out, depth + 1)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            _json_launchers(x, "%s[%d]" % (path, i), out, depth + 1)
    return out


def _secret_walk(v, path, out, depth=0):
    """Secret-looking KEYS and VALUES anywhere in a parsed JSON document, plus a literal value under a
    credential-named key (R6 for MCP files: a credential in an MCP file would be recorded, printed and
    tracked). The values themselves are never put in the message."""
    if depth > 64:
        return
    if isinstance(v, dict):
        for k in sorted(v, key=str):
            sub = "%s.%s" % (path, _safe_key(k)) if path else _safe_key(k)
            if looks_secret(str(k)):
                out.append("%s: a key looks like a credential (value withheld)" % sub)
            x = v[k]
            if isinstance(x, str) and _SECRET_KEY_RE.search(str(k)) and len(x) >= 8 and not _HEADER_VALUE_RE.match(x):
                out.append("%s: literal value under a credential-named key (value withheld; use a ${NAME} reference)" % sub)
            _secret_walk(x, sub, out, depth + 1)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            _secret_walk(x, "%s[%d]" % (path, i), out, depth + 1)
    elif isinstance(v, str) and looks_secret(v):
        out.append("%s: secret-looking value (value withheld; reference env var NAMES only)" % (path or "<top>"))


def mcp_document(tree, rel):
    """Parse the MCP JSON file REL of TREE. Raises ValueError or EngineError (never returns None)."""
    if not rel.endswith(".json"):
        raise ValueError("MCP server files must be JSON (*.json)")
    text = _read_nofollow(os.path.join(tree, rel), MAX_FILE_BYTES, rel)
    try:
        doc = json_loads(text)
        _json_launchers(doc, "", [])
    except RecursionError:
        raise ValueError("nested too deeply")
    return doc


# R22 server entry SHAPES (round 7: an allow-list). The MCP file is {"mcpServers": {<key>: <entry>}} and nothing
# else. An entry is exactly one of
#   (a) stdio: has "command" (checked by mcp_launch_problems); type / transport, if present, are "stdio"; it never
#       carries an endpoint key (url, headers, endpoint, ...);
#   (b) remote: no "command"; keys only from REMOTE_KEYS; type / transport http, sse or streamable-http; an https URL
#       without userinfo, query or fragment whose host[:port] is listed in BOTH provides.mcp[].network and
#       capabilities.network; the provides.mcp entry has transport http; the entry key IS the provides.mcp name;
#       header values are ${NAME} references (optionally "Bearer ${NAME}") to names in the server's env_vars.
# capabilities.shell never admits a remote entry. Every server key and every endpoint is in the consent list.
REMOTE_KEYS = frozenset(("type", "transport", "url", "headers", "description", "timeout", "disabled", "name"))
REMOTE_TYPES = frozenset(("http", "sse", "streamable-http"))
_ENDPOINT_NORM = frozenset(("url", "headers", "serverurl", "endpoint", "httpurl", "baseurl", "uri", "sseurl", "host",
                            "hostname", "proxy", "endpoints", "urls"))
_HEADER_NAME_RE = re.compile(r"[A-Za-z][A-Za-z0-9-]{0,63}\Z")
_HEADER_VALUE_RE = re.compile(r"(?:Bearer |Basic )?\$\{([A-Z_][A-Z0-9_]{0,127})\}\Z")
_URL_PATH_RE = re.compile(r"(?:/[A-Za-z0-9._~%-]+)*/?\Z")


def mcp_shape_problems(doc, s, m):
    """Problems with the document shape and the entry shapes of one MCP file (R22, allow-list)."""
    f = s["file"]
    if not isinstance(doc, dict):
        return ["%s: the MCP file must be a JSON object {\"mcpServers\": {...}}" % f]
    errs = ["%s: top-level key %s is not allowed (only mcpServers)" % (f, _safe_key(k))
            for k in sorted(doc, key=str) if k != "mcpServers"]
    servers = doc.get("mcpServers", {})
    if not isinstance(servers, dict):
        return errs + ["%s: mcpServers must be an object" % f]
    caps_net = set((m.get("capabilities") or {}).get("network") or [])
    srv_net = set(s.get("network") or [])
    env_vars = set(s.get("env_vars") or [])
    for key in sorted(servers, key=str):
        ent, where = servers[key], "%s mcpServers.%s" % (f, _safe_key(key))
        if not isinstance(ent, dict):
            errs.append("%s: a server entry must be an object" % where)
            continue
        for k in sorted(ent, key=str):
            if _knorm(k) in _ENDPOINT_NORM and "command" in ent:  # RULE:R22-shape-stdio
                errs.append("%s: a command entry may not carry the endpoint key %s" % (where, _safe_key(k)))
        for k in ("type", "transport"):
            if "command" in ent and k in ent and ent[k] != "stdio":
                errs.append("%s: %s of a command entry must be stdio" % (where, k))
        if "command" in ent:
            continue
        # remote shape
        for k in sorted(ent, key=str):
            if k not in REMOTE_KEYS:  # RULE:R22-shape-keys
                errs.append("%s: key %s is not allowed in a remote entry (allowed: %s)"
                            % (where, _safe_key(k), ", ".join(sorted(REMOTE_KEYS))))
        for k in ("type", "transport"):
            if k in ent and ent[k] not in REMOTE_TYPES:
                errs.append("%s: %s must be one of %s" % (where, k, ", ".join(sorted(REMOTE_TYPES))))
        url = ent.get("url")
        if not isinstance(url, str) or not url:
            errs.append("%s: needs a command (stdio) or a url (remote)" % where)
            continue
        if key != s["name"] or s.get("transport") != "http" or not srv_net:  # RULE:R22-shape-declared
            errs.append("%s: a remote server must be the provides.mcp entry of the same name with transport: http "
                        "and network: [host]; capabilities.shell does not admit an endpoint" % where)
        try:
            u = urllib.parse.urlsplit(url)
            port = u.port
        except ValueError:
            errs.append("%s: url is not valid" % where)
            continue
        netloc = (u.hostname or "").lower() + (":%d" % port if port else "")
        if (u.scheme != "https" or "@" in u.netloc or u.query or u.fragment or not u.hostname  # RULE:R22-shape-url
                or not _URL_PATH_RE.match(u.path) or ".." in u.path.split("/") or len(url) > 300
                or u.netloc.lower() != netloc):
            errs.append("%s: url must be https://host[:port]/path without userinfo, query or fragment" % where)
        elif netloc not in {h.lower() for h in srv_net} or netloc not in {h.lower() for h in caps_net}:
            errs.append("%s: host %s must be listed in provides.mcp network and in capabilities.network"
                        % (where, disp(netloc)))
        hd = ent.get("headers", {})
        if not isinstance(hd, dict):
            errs.append("%s: headers must be an object" % where)
            continue
        for hk in sorted(hd, key=str):
            hv = hd[hk]
            mt = _HEADER_VALUE_RE.match(hv) if isinstance(hv, str) else None
            if not isinstance(hk, str) or not _HEADER_NAME_RE.match(hk):  # RULE:R22-shape-header
                errs.append("%s: header name %s is not a plain token" % (where, _safe_key(hk)))
            elif not mt or mt.group(1) not in env_vars:
                errs.append("%s: header %s must be a ${NAME} reference to a name in the server's env_vars"
                            % (where, _safe_key(hk)))
    return errs


def _argv_size(launchers):
    n = 0
    for _w, d in launchers:
        n += len(json.dumps([d.get("command"), d.get("args")], default=str))
    return n


def mcp_problems(tree, m):
    """R22: the launch commands an extension's MCP servers declare, in the manifest and inside each MCP
    file, are checked by mcp_command_problems / mcp_launch_problems (allow-list); an MCP file that is not
    readable JSON, holds a secret-looking key or value, or holds more launchers than MAX_LAUNCHERS is a
    problem; every capabilities.shell name must be an MCP server of this extension."""
    errs = []
    servers = (m.get("provides") or {}).get("mcp") or []
    shell = set((m.get("capabilities") or {}).get("shell") or [])
    for n in sorted(shell - {s["name"] for s in servers}):
        errs.append("capabilities.shell: %s is not an MCP server of this extension" % n)
    for s in servers:
        declared = s["name"] in shell
        if not declared:
            errs += ["provides.mcp %s: environment name %s is not on the allow-list of inert names; list the "
                     "server in capabilities.shell to declare it" % (s["name"], _safe_key(n))
                     for n in s.get("env_vars") or [] if not env_inert(n)]  # RULE:R22-env-vars
        if s.get("command") is not None:
            errs += mcp_command_problems("provides.mcp %s" % s["name"], s["command"], s.get("args"), declared,
                                         None, tree, s.get("env_vars"))
        try:
            doc = mcp_document(tree, s["file"])
        except EngineError as ex:
            errs.append("%s: %s" % (s["file"], ex.msg))
            continue
        except ValueError as ex:  # RULE:R22-json
            errs.append("%s: not a readable JSON MCP file (%s)" % (s["file"], str(ex)[:120]))
            continue
        sec = []
        _secret_walk(doc, "", sec)
        errs += ["%s %s" % (s["file"], x) for x in sec[:20]]  # RULE:R22-secret-walk
        errs += mcp_shape_problems(doc, s, m)  # RULE:R22-shape
        launchers = _json_launchers(doc, "", [])
        if len(launchers) > MAX_LAUNCHERS or _argv_size(launchers) > MAX_ARGV_BYTES:  # RULE:R22-bounds
            errs.append("%s: more than %d launch mappings or more than %d bytes of commands and arguments"
                        % (s["file"], MAX_LAUNCHERS, MAX_ARGV_BYTES))
            continue
        for where, d in launchers:
            errs += mcp_launch_problems("%s %s" % (s["file"], where), d, declared, tree, s.get("env_vars"))
    return errs


def content_problems(tree, m):
    """Everything the agent or an MCP client would run or read from the tree: R21 + R22."""
    return construct_problems(tree, m) + mcp_problems(tree, m)


def _sha_or_unreadable(p):
    try:
        if not stat.S_ISREG(os.lstat(p).st_mode):
            return "not-a-regular-file"
        return _sha_file(p)
    except (OSError, EngineError):
        return "unreadable"


def bound_files(tree, m):
    """Relpaths whose CONTENT is part of the consent (I3): hook scripts, MCP files, executables, and every
    file below a command directory the agent may execute or inject from (capabilities.agent_shell /
    reads_files)."""
    prov = m.get("provides") or {}
    caps = m.get("capabilities") or {}
    rels = {h["command"] for h in prov.get("hooks") or []} | {s["file"] for s in prov.get("mcp") or []}
    rels |= set(caps.get("executes") or [])
    risky = set(caps.get("agent_shell") or []) | set(caps.get("reads_files") or [])
    for c in prov.get("commands") or []:
        if c["name"] not in risky:
            continue
        top = os.path.join(tree, "commands", c["name"])
        if not os.path.isdir(top) or os.path.islink(top):
            continue
        for dp, dns, fns in os.walk(top, onerror=_walk_error):
            dns.sort()
            for n in fns:
                rels.add(os.path.relpath(os.path.join(dp, n), tree))
    for s in prov.get("skills") or []:
        if s["name"] in risky:
            rels.add(s["path"])
    return sorted(rels)


# ── environment / state ────────────────────────────────────────────────────────────────────
_HARNESS = {"ok": False}
NONCE_FILE = ".constitution-ext-test-nonce"


def test_harness_ok(project):
    """True only inside a test sandbox: CONSTITUTION_EXT_TEST_NONCE (32-128 lowercase hex) must equal the
    content of <parent of the project>/.constitution-ext-test-nonce, a regular file owned by this user
    with no group/other permissions. Without that proof every test seam is inert (R19)."""
    nonce = os.environ.get("CONSTITUTION_EXT_TEST_NONCE", "")
    if not project or not re.fullmatch(r"[0-9a-f]{32,128}", nonce):
        return False
    f = os.path.join(os.path.dirname(os.path.abspath(project)), NONCE_FILE)
    try:
        fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return False
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_mode & 0o077 or st.st_size > 512:
            return False
        got = os.read(fd, 512).decode("ascii", "replace").strip()
    finally:
        os.close(fd)
    return hmac.compare_digest(got, nonce)


RACE_HOOK = None  # unit tests only: an in-process callable(stage); a process cannot be given one from outside


def race_point(stage):
    """Deterministic race seam: lets an in-process test change the source tree at a named moment (the TOCTOU
    tests of I2). None in production, and nothing external can set it (not an environment variable)."""
    if RACE_HOOK is not None:
        RACE_HOOK(stage)


def kill_point(stage):
    """Chaos-test hook: SIGKILL self at STAGE when CONSTITUTION_EXT_TEST_MODE=1, KILL_AT matches, AND the
    run is proven to be inside a test sandbox (test_harness_ok). Inert otherwise (R19)."""
    if _HARNESS["ok"] and os.environ.get("CONSTITUTION_EXT_TEST_MODE") == "1" \
            and os.environ.get("CONSTITUTION_EXT_TEST_KILL_AT") == stage:  # RULE:R19-kill-guard
        sys.stdout.flush()
        os.kill(os.getpid(), signal.SIGKILL)


_GIT_KEEP_ENV = ("PATH", "HOME", "TMPDIR", "SSH_AUTH_SOCK", "SYSTEMROOT")
_GIT_CONFIG = ("core.hooksPath=/dev/null", "core.symlinks=false", "core.fsmonitor=false",
               "core.attributesFile=/dev/null", "core.untrackedCache=false", "submodule.recurse=false",
               "protocol.allow=never", "protocol.file.allow=always", "protocol.https.allow=always",
               "protocol.ssh.allow=always", "protocol.ext.allow=never", "uploadpack.allowFilter=false")


def _git_env():
    """Minimal environment for git (R15): nothing inherited except PATH/HOME/TMPDIR/SSH_AUTH_SOCK; every
    GIT_* variable from the caller (GIT_DIR, GIT_WORK_TREE, GIT_CONFIG_*, GIT_SSH_COMMAND, ...) is dropped
    and the system and global configuration are not read."""
    env = {k: os.environ[k] for k in _GIT_KEEP_ENV if k in os.environ}  # RULE:R15-env-scrub
    env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
                "GIT_ASKPASS": "/bin/false", "SSH_ASKPASS": "/bin/false", "GIT_ALLOW_PROTOCOL": "file:https:ssh",
                "GIT_LFS_SKIP_SMUDGE": "1", "LC_ALL": "C"})
    return env


def _git(args, cwd=None, check=False):
    cmd = ["git"]
    for c in _GIT_CONFIG:
        cmd += ["-c", c]
    cmd = cmd + args  # RULE:R15-git-config
    r = subprocess.run(cmd, cwd=cwd, env=_git_env(), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, universal_newlines=True, errors="replace")
    if check and r.returncode != 0:
        raise EngineError(EXIT_FAIL, "git %s failed: %s" % (args[0], redact(r.stderr.strip()[:300])))
    return r


GIT_ATTRIBUTES = "* -filter -text -ident -diff -merge -export-subst -working-tree-encoding\n"


def _harden_clone(clone):
    """Before checkout: info/attributes (highest precedence) switches off every filter driver, text
    conversion, ident expansion and merge/diff drivers for all paths (R15)."""
    info = os.path.join(clone, ".git", "info")
    os.makedirs(info, exist_ok=True)
    fd = os.open(os.path.join(info, "attributes"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as f:
        f.write(GIT_ATTRIBUTES)  # RULE:R15-attributes


def _git_tree_problems(clone, commit):
    """Refuse symlink (120000) and gitlink/submodule (160000) entries before checkout (R15)."""
    r = _git(["-C", clone, "ls-tree", "-r", "-z", "--full-tree", commit])
    if r.returncode != 0:
        return ["cannot list the commit tree: %s" % disp(r.stderr.strip()[:200])]
    errs = []
    for rec in r.stdout.split("\0"):
        if not rec:
            continue
        meta, _tab, path = rec.partition("\t")
        mode = meta.split(" ", 1)[0]
        if mode == "120000":  # RULE:R15-git-symlink
            errs.append("%s: symlinks are not allowed in an extension" % disp(path))
        elif mode == "160000":
            errs.append("%s: git submodules are not allowed in an extension" % disp(path))
    return errs


URL_RE = re.compile(r"(https://|ssh://|file://|git@[A-Za-z0-9.-]+:)[^\s]+\Z")


def url_problem(u):
    """None if U is an acceptable git source URL, else the reason (never containing U) (R16)."""
    if not isinstance(u, str) or not u or len(u) > 2048:
        return "invalid URL"
    if u.startswith("-"):
        return "must not start with '-'"
    if bad_chars(u):
        return "control, bidi/format or separator characters in the URL"
    if not URL_RE.match(u):
        return "not an allowed git URL (https://, ssh://, file://, git@host:path)"
    if "::" in u:  # RULE:R16-transport-helper
        return "transport helpers (::) are not allowed"
    m = re.match(r"(https|ssh|file)://([^/?#]*)", u)
    if m and "@" in m.group(2):  # RULE:R16-userinfo
        user = m.group(2).rsplit("@", 1)[0]
        if m.group(1) != "ssh" or ":" in user or not re.fullmatch(r"[A-Za-z0-9._-]{1,32}", user) or looks_secret(user):
            return "credentials (userinfo) in the URL are not allowed; use a credential helper or SSH keys"
    if looks_secret(u):  # RULE:R16-secret-url
        return "secret-looking value in the URL (value withheld)"
    q = re.split(r"[?#]", u, maxsplit=1)
    if len(q) == 2:
        for part in re.split(r"[&;?#]", q[1]):
            if CRED_PARAM_RE.match(part.split("=", 1)[0]):  # RULE:R16-query-token
                return "credential-like query parameter in the URL is not allowed (value withheld)"
    return None


CRED_PARAM_RE = re.compile(r"(?i)(private[_-]?token|access[_-]?token|auth[_-]?token|token|auth|key|api[_-]?key|"
                           r"password|passwd|pass|pwd|secret|client[_-]?secret|sig|signature|credentials?|session)\Z")
_REDACT_RES = ((re.compile(r"(?i)([?&;#][A-Za-z0-9_.-]*=)[^&;#\s'\"]*"), r"\1<redacted>"),
               (re.compile(r"(://)[^/@\s]*@"), r"\1<redacted>@"))


def redact(s):
    """Text for messages: URL userinfo and every query-parameter value replaced by <redacted>."""
    s = disp(s)
    for r, rep in _REDACT_RES:
        s = r.sub(rep, s)
    return s


_SECRET_PREFIX_RE = re.compile(r"(?i)(gh[pousr]_|github_pat_|glpat-|sk-|xox[abprs]-|akia|asia|aiza|ya29\.|eyj)")


def secret_shaped_id(s):
    """True for a short identifier (waiver id) that looks like a credential or token."""
    if _SECRET_PREFIX_RE.match(s) or looks_secret(s):
        return True
    return len(s) >= 20 and bool(re.search(r"[A-Z]", s) and re.search(r"[a-z]", s) and re.search(r"[0-9]", s))


def _has_constitution(d):
    return d and os.path.isfile(os.path.join(d, "Constitution.md"))


def resolve_root(opt):
    if opt:
        r = os.path.abspath(opt)
        if not _has_constitution(r):
            raise EngineError(EXIT_REFUSED, "--root %s: no Constitution.md there" % opt)
        return r
    env = os.environ.get("CONSTITUTION_DIR")
    if env and _has_constitution(env):
        return os.path.abspath(env)
    # Implicit discovery has ONE source: the place this engine itself lives, <root>/scripts/constitution_ext with a
    # Constitution.md at <root>. The cwd is never searched: a walk up from it can land in a foreign project through
    # a symlinked ancestor (round 6, IMPORTANT-3). RULE:R23-own-location
    here = os.path.realpath(HERE)
    cand = os.path.dirname(os.path.dirname(here))
    if os.path.basename(here) == "constitution_ext" and os.path.basename(os.path.dirname(here)) == "scripts" \
            and _has_constitution(cand):
        return cand
    raise EngineError(EXIT_REFUSED, "constitution root not found: it is discovered only when this engine sits at "
                                    "<root>/scripts/constitution_ext next to a Constitution.md; pass --root DIR")


def _check_project_is_cwd_toplevel(project, explicit):
    """A project root that was discovered (not given with --project-root) must be the git top level of the current
    directory, so a command run in one project can never change another one (R23)."""
    if explicit or not project:
        return
    r = _git(["-C", os.getcwd(), "rev-parse", "--show-toplevel"])
    top = os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None
    if top is None or top != os.path.realpath(project):  # RULE:R23-project-is-cwd
        raise EngineError(EXIT_REFUSED, "the discovered project %s is not the git top level of the current directory "
                                        "(%s); refusing to change it. cd into that project, or pass --project-root DIR"
                          % (disp(project), disp(top or "not a git repository")))


def resolve_project(opt, root):
    if opt:
        p = os.path.abspath(opt)
        if not os.path.isdir(p):
            raise EngineError(EXIT_REFUSED, "--project-root %s: not a directory" % opt)
        return p
    r = _git(["-C", root, "rev-parse", "--show-superproject-working-tree"])
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    r = _git(["-C", os.getcwd(), "rev-parse", "--show-toplevel"])
    if r.returncode == 0 and r.stdout.strip():
        top = os.path.realpath(r.stdout.strip())
        if top != os.path.realpath(root):
            return top
    return None


def layout_of(root, project):
    if not project:
        return "standalone"
    rel = os.path.relpath(os.path.realpath(root), os.path.realpath(project))
    if rel in ("constitution", "submodules/constitution"):
        return rel
    return "other:" + rel


def constitution_version(root):
    v = os.environ.get("CONSTITUTION_EXT_CONSTITUTION_VERSION")
    if v and _HARNESS["ok"]:  # honoured only inside a proven test sandbox (R19); Engine refuses otherwise
        return v
    r = _git(["-C", root, "describe", "--tags", "--abbrev=0", "--match", "helixconstitution-v*"])
    if r.returncode == 0:
        t = r.stdout.strip()
        if t.startswith("helixconstitution-v") and re.fullmatch(r"[0-9]+(\.[0-9]+)*", t[len("helixconstitution-v"):]):
            return t[len("helixconstitution-v"):]
    return None


TRASH_RE = re.compile(r"\.trash-[0-9]+-[0-9a-f]{8}\Z")
STAGING_RE = re.compile(r"\.(staging|trash)-([0-9]+)-[0-9a-f]{8}\Z")
SNAP_STAGE_RE = re.compile(r"\.stage-([0-9]+)-[0-9a-f]{8}\Z")
TMP_RE = re.compile(r".*\.tmp-([0-9]+)-[0-9a-f]{8}\Z")
GITIGNORE_LINES = ("extensions.txn", "*.tmp-*", "extensions.state/")
STATE_DIR = "extensions.state"
WIRING_KEYS = frozenset(("id", "command", "agent", "path", "root", "kind", "target", "sha256"))
SNAP_DIR = "extensions.snapshots"  # consented copies of command directories the Claude shims link to (I2)
WIRING_RECORD = "wiring.json"  # local, HMAC-signed copy of the entries this checkout created (R20)
STATE_FILES = ("extensions.lock.yml", "extensions.wiring.yml", "extensions.catalog.json", "extensions.audit.log",
               "extensions.txn", ".gitignore")


def _inside(path, parent):
    """True iff PATH equals PARENT or lies below it (both compared as given; callers pass realpaths)."""
    return path == parent or path.startswith(parent.rstrip(os.sep) + os.sep)


def _rel_ok(r):
    """A normalised project-relative path ('.' allowed): not absolute, no '..' escape, no odd characters."""
    return isinstance(r, str) and 0 < len(r) <= 1024 and not os.path.isabs(r) and os.path.normpath(r) == r \
        and r != ".." and not r.startswith("../") and not bad_chars(r) and "\\" not in r


def json_loads(text):
    """json.loads for untrusted input: deep nesting is a ValueError with a reason, never a RecursionError."""
    def pairs(items):
        out = {}
        for k, v in items:
            if k in out:  # RULE:R22-dup-key
                raise ValueError("duplicate key %s" % _safe_key(k))
            out[k] = v
        return out
    try:
        return json.loads(text, object_pairs_hook=pairs)
    except RecursionError:
        raise ValueError("nested too deeply")


def _open_regular(path, what):
    """Open PATH read-only without following a symlink and without blocking on a FIFO or device, and prove
    the opened object is a regular file (M4). Returns the fd; raises EngineError."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # RULE:M4-open-nonblock
    except OSError as ex:
        raise EngineError(EXIT_VERIFY, "%s unreadable (%s; symlinks are not followed)" % (what, ex.strerror))
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):  # RULE:M4-open-regular
        os.close(fd)
        raise EngineError(EXIT_VERIFY, "%s is not a regular file" % what)
    return fd


def _read_nofollow(path, limit, what):
    """Read a small regular file without following a symlink (R18). Raises EngineError."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)  # never blocks on a FIFO
    except OSError as ex:
        raise EngineError(EXIT_VERIFY, "%s unreadable (%s; symlinks are not followed)" % (what, ex.strerror))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise EngineError(EXIT_VERIFY, "%s is not a regular file" % what)
        if st.st_size > limit:
            raise EngineError(EXIT_VERIFY, "%s is larger than %d bytes" % (what, limit))
        chunks, n = [], 0
        while True:
            b = os.read(fd, 65536)
            if not b:
                break
            n += len(b)
            if n > limit:
                raise EngineError(EXIT_VERIFY, "%s is larger than %d bytes" % (what, limit))
            chunks.append(b)
    finally:
        os.close(fd)
    try:
        return b"".join(chunks).decode("utf-8")
    except UnicodeDecodeError:
        raise EngineError(EXIT_VERIFY, "%s is not UTF-8" % what)


class Engine:
    def __init__(self, opts):
        self.o = opts
        self.json = opts["json"]
        self.dry = opts["dry_run"]
        self.root = resolve_root(opts.get("root"))
        self.project = resolve_project(opts.get("project_root"), self.root)
        self.ext_dir = os.path.join(self.root, "extensions")
        self.inst_dir = os.path.join(self.ext_dir, "_installed")
        self.safe_rm = os.path.join(HERE, "..", "lib", "safe_rm.sh")
        if self.project and os.path.realpath(self.project) == os.path.realpath(self.root):  # RULE:M1-project-not-root
            raise EngineError(EXIT_REFUSED, "--project-root is the constitution root itself (%s); pass the consuming "
                                            "project's directory" % self.root)
        self.state = os.path.join(self.project, ".constitution") if self.project else None
        self._lockfds = []
        self._locked = False
        self._manifest_cache = {}
        self._journal_bad = None
        self._wsigned, self._wsig_problem = set(), None
        self._wstage, self._wn = None, 0
        _HARNESS["ok"] = test_harness_ok(self.project)
        if os.environ.get("CONSTITUTION_EXT_CONSTITUTION_VERSION") and not _HARNESS["ok"]:  # RULE:R19-version-guard
            raise EngineError(EXIT_REFUSED, "WARNING: CONSTITUTION_EXT_CONSTITUTION_VERSION is a TEST-ONLY override and "
                                            "is refused outside a test sandbox; unset it (version detection uses "
                                            "git describe --match 'helixconstitution-v*')")

    # ── output ──
    def say(self, *a):
        if not self.json:
            print(*a)

    def err(self, msg):
        print("constitution_ext: " + msg, file=sys.stderr)

    # ── state paths ──
    def p(self, name):
        return os.path.join(self.state, name)

    def need_project(self):
        if not self.project:
            raise EngineError(EXIT_REFUSED, "no consumer project found (pass --project-root DIR)")

    def _check_shared_dirs(self):
        """RULE:A4-shared-dirs: <root>/extensions and <root>/extensions/_installed are the SHARED part of the root.
        When they exist they must be real directories owned by this user (or by root when run as root); a symlink
        there would let a sweep, an add or a remove act on whatever the link points at."""
        for d in (self.ext_dir, self.inst_dir):
            if not os.path.lexists(d):
                continue
            st = os.lstat(d)
            if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
                raise EngineError(EXIT_REFUSED, "%s is a symlink or not a real directory; refusing to install, "
                                                "remove or clean up through it" % d)
            if st.st_uid != os.geteuid() and os.geteuid() != 0:
                raise EngineError(EXIT_REFUSED, "%s is not owned by you; refusing to act on it" % d)

    def _check_state_dir(self):
        """The state directory must be a real directory, never a symlink (R18)."""
        if self.state and os.path.lexists(self.state):
            st = os.lstat(self.state)
            if not stat.S_ISDIR(st.st_mode):
                raise EngineError(EXIT_REFUSED, "%s is not a real directory (a symlink or a file); refusing to use it" % self.state)
            sd = self.p(STATE_DIR)
            for dd in (sd, self.p(SNAP_DIR)):  # RULE:R18-snapshots-dir
                if os.path.lexists(dd) and not stat.S_ISDIR(os.lstat(dd).st_mode):
                    raise EngineError(EXIT_REFUSED, "%s is not a real directory; refusing to use it" % dd)
            # every state file is checked BEFORE any change, so no command half-completes and then
            # fails on a symlinked audit log, lock or wiring file (R18)
            files = [self.p(n) for n in STATE_FILES] + [os.path.join(sd, n) for n in ("key", WIRING_RECORD)]
            for f in files:
                if os.path.lexists(f) and not stat.S_ISREG(os.lstat(f).st_mode):  # RULE:R18-upfront
                    raise EngineError(EXIT_VERIFY, "%s is not a regular file (a symlink?); refusing to run "
                                                   "(nothing was changed)" % f)

    def acquire(self, create, mutating=None):
        """One exclusive flock on the project directory and on the root's extensions/ directory for the
        whole command (R13); then, for a MUTATING command (default: CREATE), recovery of an interrupted
        transaction and removal of dead staging directories; a read-only command only reports a pending
        journal (I3). CREATE makes the state dir."""
        mutating = create if mutating is None else mutating
        if not self.project:
            return
        if not self._locked:
            if mutating:
                _check_project_is_cwd_toplevel(self.project, bool(self.o.get("project_root")))
            self._check_state_dir()
            if mutating:
                self._check_shared_dirs()  # RULE:A4-shared-dirs
            for d in (self.project, self.root):  # the root always exists (extensions/ may not yet)
                fd = os.open(d, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
                fcntl.flock(fd, fcntl.LOCK_EX)  # RULE:R13-lock
                self._lockfds.append(fd)
            self._locked = True
            self._check_state_dir()
            if not self.dry and os.path.isdir(self.state):
                self.recover(mutating)
        if create:
            self.ensure_state()

    def release(self):
        """Drop the R13 locks (process exit also drops them; library callers use this)."""
        for fd in self._lockfds:
            os.close(fd)
        self._lockfds, self._locked = [], False

    def ensure_state(self):
        if self.dry or not self.state:
            return
        self._check_state_dir()
        if not os.path.lexists(self.state):
            os.mkdir(self.state, 0o755)
        self._ensure_gitignore()

    def _ensure_gitignore(self):
        """<project>/.constitution/.gitignore keeps the journal, temp files and the local state record
        out of git; written idempotently, existing lines kept (R12, R17)."""
        path = self.p(".gitignore")
        text = _read_nofollow(path, 65536, path) if os.path.lexists(path) else ""
        have = text.splitlines()
        missing = [ln for ln in GITIGNORE_LINES if ln not in have]
        if not missing:
            return
        head = [] if have else ["# Generated by constitution_ext: local state that must never be committed."]
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            pre = "\n" if text and not text.endswith("\n") else ""
            f.write(pre + "\n".join(head + missing) + "\n")

    # ── safe writes (R18) ──
    def write_atomic(self, path, data, stage=None, mode=0o644):
        if os.path.lexists(path) and not stat.S_ISREG(os.lstat(path).st_mode):
            raise EngineError(EXIT_REFUSED, "%s is not a regular file (symlink?); refusing to write through it" % path)
        tmp = "%s.tmp-%d-%s" % (path, os.getpid(), os.urandom(4).hex())
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)  # RULE:R18-nofollow
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        if stage:
            kill_point(stage)
        os.replace(tmp, path)
        dfd = os.open(os.path.dirname(path), os.O_RDONLY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)

    def audit(self, op, ext_id, detail=""):
        import datetime
        t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        fd = os.open(self.p("extensions.audit.log"), os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(json.dumps({"t": t, "op": op, "id": ext_id, "detail": detail}, sort_keys=True) + "\n")

    # ── lock file ──
    def read_lock(self):
        path = self.p("extensions.lock.yml") if self.state else None
        if not path or not os.path.lexists(path):
            return {}
        try:
            d = ext_yaml.parse(_read_nofollow(path, STATE_LIMITS["max_bytes"], "lock file"), **STATE_LIMITS)
        except ext_yaml.YamlError as ex:
            raise EngineError(EXIT_VERIFY, "lock file unreadable: %s" % ex)
        out = {}
        for e in d.get("extensions") or []:
            if not isinstance(e, dict) or not isinstance(e.get("id"), str) or not ID_RE.match(e["id"]):
                raise EngineError(EXIT_VERIFY, "lock file has a malformed entry")
            out[e["id"]] = e
        return out

    def write_lock(self, entries, stage=None, force=False):
        doc = {"lock_version": "1", "extensions": [entries[k] for k in sorted(entries)]}
        data = "# Generated by constitution_ext (scripts/constitution_ext). Do not edit by hand.\n" + ext_yaml.dump(doc)
        ext_yaml.parse(data, **STATE_LIMITS)  # never write a lock this engine could not read back
        path = self.p("extensions.lock.yml")
        same = False
        if os.path.lexists(path):
            same = _read_nofollow(path, STATE_LIMITS["max_bytes"], "lock file") == data
        if same and not force:
            return False
        self.write_atomic(path, data, stage)
        return not same

    # ── local state records (R17) ──
    def _sd(self):
        return self.p(STATE_DIR)

    def _key(self, create):
        kp = os.path.join(self._sd(), "key")
        if os.path.lexists(kp):
            try:
                fd = os.open(kp, os.O_RDONLY | os.O_NOFOLLOW)
            except OSError as ex:
                raise EngineError(EXIT_VERIFY, "state key unreadable: %s" % ex.strerror)
            try:
                st = os.fstat(fd)
                if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077:
                    raise EngineError(EXIT_VERIFY, "state key %s must be a regular file with mode 0600" % kp)
                k = os.read(fd, 256).strip()
            finally:
                os.close(fd)
            if not re.fullmatch(rb"[0-9a-f]{64}", k):
                raise EngineError(EXIT_VERIFY, "state key %s is malformed" % kp)
            return k
        if not create:
            return None
        sd = self._sd()
        if not os.path.lexists(sd):
            os.mkdir(sd, 0o700)
        k = os.urandom(32).hex().encode()
        fd = os.open(kp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(k + b"\n")
            f.flush()
            os.fsync(f.fileno())
        return k

    @staticmethod
    def _mac(key, eid, entry):
        msg = json.dumps({"id": eid, "entry": entry}, sort_keys=True, separators=(",", ":")).encode()
        return hmac.new(key, msg, hashlib.sha256).hexdigest()

    @staticmethod
    def _jmac(key, j):
        body = {k: v for k, v in j.items() if k != "mac"}
        msg = b"journal-" + str(j.get("op")).encode() + b"\0" + json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
        return hmac.new(key, msg, hashlib.sha256).hexdigest()

    def make_record(self, eid, entry):
        return {"id": eid, "entry": entry, "mac": self._mac(self._key(True), eid, entry)}

    def _record_valid(self, rec, key):
        return isinstance(rec, dict) and isinstance(rec.get("id"), str) and ID_RE.match(rec["id"]) \
            and isinstance(rec.get("entry"), dict) and isinstance(rec.get("mac"), str) and key is not None \
            and hmac.compare_digest(rec["mac"], self._mac(key, rec["id"], rec["entry"]))  # RULE:R17-mac

    def write_record(self, rec):
        self.write_atomic(os.path.join(self._sd(), rec["id"] + ".json"),
                          json.dumps(rec, sort_keys=True) + "\n", mode=0o600)

    def delete_record(self, eid):
        p = os.path.join(self._sd(), eid + ".json")
        if os.path.lexists(p):
            os.unlink(p)

    def record_problems(self, eid, entry):
        """[] if the tracked lock ENTRY matches the local HMAC-protected state record, else precise problems."""
        p = os.path.join(self._sd(), eid + ".json")
        if not os.path.lexists(p):
            return ["no local state record for %s (lock entry not created by this engine in this checkout, "
                    "or the record was deleted); run enable (bundled) or remove + add (installed) to re-consent" % eid]
        key = self._key(False)
        if key is None:
            return ["local state key %s is missing; state records cannot be checked" % os.path.join(self._sd(), "key")]
        try:
            rec = json_loads(_read_nofollow(p, 1 << 20, "state record"))
        except ValueError:
            rec = None
        if not self._record_valid(rec, key) or rec["id"] != eid:
            return ["local state record for %s fails its integrity check (forged or corrupted)" % eid]
        probs = []
        for k in sorted(set(entry) | set(rec["entry"])):  # RULE:R17-compare
            if entry.get(k) != rec["entry"].get(k):
                probs.append("lock field %s differs from the local state record (lock edited outside the engine?)" % k)
        return probs

    def commit(self, lock, changed, stage=None, force=False, outer=False):
        """Write LOCK and the state records of the CHANGED ids (records deleted for ids no longer in LOCK).
        Without an OUTER transaction the signed records go to a 'commit' journal first, so an interrupted
        run rolls the records forward on the next run when (and only when) the lock already matches."""
        recs = [self.make_record(i, lock[i]) for i in sorted(changed) if i in lock]
        dels = sorted(i for i in changed if i not in lock)
        if not outer:
            self._refuse_bad_journal()  # RULE:F2-keep-bad-journal: never overwrite (and so destroy) a journal we ignored
            self.write_atomic(self.p("extensions.txn"), json.dumps({"op": "commit", "records": recs, "deletes": dels}))
        wrote = self.write_lock(lock, stage=stage, force=force)
        for r in recs:
            self.write_record(r)
        for i in dels:
            self.delete_record(i)
        if not outer:
            os.unlink(self.p("extensions.txn"))
        return wrote

    # ── wiring file (R11, R20) ──
    # Entries are project-relative (portable: a clone verifies and unwires them): `root` and `path` are
    # relative to the project, a Claude `target` is the link text, relative to the shim's directory.
    def _wabs(self, rel):
        return os.path.normpath(os.path.join(self.project, rel))

    def _shim_rel(self, agent, root_rel, name):
        return os.path.normpath(os.path.join(root_rel, {
            "claude": os.path.join(".claude", "skills", name),
            "opencode": os.path.join(".opencode", "commands", name + ".md"),
            "gemini": os.path.join(".gemini", "commands", name + ".toml"),
            "qwen": os.path.join(".qwen", "commands", name + ".toml"),
            "pi": os.path.join(".pi", "prompts", name + ".md")}[agent]))

    def _snap(self, eid, cmd, digest):
        return os.path.join(self.state, SNAP_DIR, eid, cmd, digest)

    def _link_texts(self, eid, cmd, shim_rel, digest=None):
        """The only link texts a Claude shim may carry: the relative path from the shim's directory to the
        consented snapshot <state>/extensions.snapshots/<id>/<cmd>/<DIGEST> (I2), or, for an entry of the old
        format (DIGEST None), to the bundled or the installed extension's commands/<cmd>; computed on resolved
        paths."""
        d = os.path.realpath(os.path.dirname(self._wabs(shim_rel)))
        if digest is not None:
            return (os.path.relpath(os.path.realpath(self._snap(eid, cmd, digest)), d),)
        return tuple(os.path.relpath(os.path.realpath(os.path.join(b, eid, "commands", cmd)), d)
                     for b in (self.ext_dir, self.inst_dir))

    def _wiring_problem(self, w):
        if not isinstance(w, dict) or set(w) != WIRING_KEYS:
            return "unexpected or missing keys"
        a, eid, cmd, root, path = w["agent"], w["id"], w["command"], w["root"], w["path"]
        if a not in WIRE_AGENTS or not isinstance(eid, str) or not ID_RE.match(eid) or not isinstance(cmd, str) \
                or not NAME_RE.match(cmd):
            return "agent, id or command name invalid"
        if not _rel_ok(root):  # RULE:R11-relative
            return ("root is not a normalised project-relative path (an absolute path is the old, non-portable "
                    "format: delete the entry and wire again)")
        proj = os.path.realpath(self.project)
        if not _inside(os.path.realpath(self._wabs(root)), proj):
            return "root is outside the project"
        if path != self._shim_rel(a, root, cmd):  # RULE:R11-shim-path
            return "path is not the shim path for this agent and command"
        if not _inside(os.path.realpath(os.path.dirname(self._wabs(path))), proj):  # RULE:R11-contained
            return "shim directory resolves outside the project"
        if a == "claude":
            dig = w["sha256"]
            if dig is not None and (not isinstance(dig, str) or not SHA256_RE.match(dig)):
                return "snapshot digest malformed"
            if w["kind"] != "symlink" or w["target"] not in self._link_texts(eid, cmd, path, dig):  # RULE:R11-link-target
                return "link target is not the consented snapshot (or, old format, the extension's commands/<command>)"
        elif w["kind"] != "file" or w["target"] is not None or not isinstance(w["sha256"], str) \
                or not SHA256_RE.match(w["sha256"]):
            return "file entry malformed"
        return None

    def read_wiring(self):
        self._wsigned, self._wsig_problem = set(), None
        path = self.p("extensions.wiring.yml") if self.state else None
        if not path or not os.path.lexists(path):
            return []
        try:
            d = ext_yaml.parse(_read_nofollow(path, STATE_LIMITS["max_bytes"], "wiring file"), **STATE_LIMITS)
        except ext_yaml.YamlError as ex:
            raise EngineError(EXIT_VERIFY, "wiring file unreadable: %s" % ex)
        entries = d.get("entries") or []
        if not isinstance(entries, list):
            raise EngineError(EXIT_VERIFY, "wiring file: entries must be a list")
        for n, w in enumerate(entries):
            why = self._wiring_problem(w)
            if why:
                raise EngineError(EXIT_VERIFY, "wiring file entry %d is invalid (%s); refusing to act on any shim. "
                                               "Inspect %s and delete the entry or the file (no shim was touched)"
                                  % (n, why, path))
        self._wsigned, self._wsig_problem = self._wiring_signed()
        return entries

    @staticmethod
    def _wkey(w):
        return json.dumps(w, sort_keys=True, separators=(",", ":"))

    @staticmethod
    def _wmac(key, entries):
        msg = json.dumps({"wiring": entries}, sort_keys=True, separators=(",", ":")).encode()
        return hmac.new(key, msg, hashlib.sha256).hexdigest()

    def _wiring_signed(self):
        """Keys of the entries in the local HMAC-signed wiring record (R20), plus a problem text when the
        record exists but fails its integrity check (it then binds nothing)."""
        p = os.path.join(self._sd(), WIRING_RECORD)
        if not os.path.lexists(p):
            return set(), None
        key = self._key(False)
        try:
            rec = json_loads(_read_nofollow(p, STATE_LIMITS["max_bytes"], "wiring record"))
        except ValueError:
            rec = None
        if not isinstance(rec, dict) or not isinstance(rec.get("entries"), list) or not isinstance(rec.get("mac"), str) \
                or key is None or not hmac.compare_digest(rec["mac"], self._wmac(key, rec["entries"])):  # RULE:R20-mac
            return set(), "local wiring record %s fails its integrity check (forged or corrupted); it binds nothing" % p
        return {self._wkey(x) for x in rec["entries"] if isinstance(x, dict)}, None

    def _marker_ok(self, w, p):
        mark = "# %s id=%s command=%s" % (MARKER, w["id"], w["command"])
        try:
            head = _read_nofollow(p, MAX_FILE_BYTES, p).splitlines()[:3]
        except EngineError:
            return False
        return any(ln.strip() == mark for ln in head)  # RULE:R20-marker

    def _unbound(self, w):
        """R20: True when acting on W would delete or overwrite a file the engine cannot prove it created:
        W is not in the local signed record, the file still has W's sha256 (so it WOULD be acted on), and the
        file carries no managed-by marker for W's id and command. A Claude link is only ever unlinked when its
        text equals an engine-computed path into the extension's own tree (R11), so it is never unbound."""
        if self._wkey(w) in self._wsigned or w["kind"] == "symlink":  # RULE:R20-signed
            return False
        p = self._wabs(w["path"])
        if not _is_reg(p) or _sha_file(p) != w["sha256"]:
            return False
        return not self._marker_ok(w, p)

    def _require_bound(self, entries):
        for n, w in enumerate(entries):
            if self._unbound(w):  # RULE:R20-refuse
                raise EngineError(EXIT_VERIFY, "wiring file entry %d (%s) is not bound: it is not in this checkout's "
                                               "signed wiring record and %s carries no managed-by marker, so it may "
                                               "name a file this engine did not create. Refusing to touch any shim; "
                                               "delete that entry from %s (the file itself was not touched)"
                                  % (n, disp(w["path"]), disp(w["path"]), self.p("extensions.wiring.yml")))

    def write_wiring(self, entries, trusted=()):
        """Write the tracked wiring file and the local signed record. Only entries already signed, or
        listed in TRUSTED (just created by wire), are signed: a carried-over unbound entry stays unbound."""
        entries = sorted(entries, key=lambda e: (e["path"], e["agent"]))
        data = "# Generated by constitution_ext. Records shims it created; unwire removes only these.\n" + \
            ext_yaml.dump({"wiring_version": "1", "entries": entries})
        ext_yaml.parse(data, **STATE_LIMITS)
        path = self.p("extensions.wiring.yml")
        changed = False
        if not (os.path.lexists(path) and _read_nofollow(path, STATE_LIMITS["max_bytes"], "wiring file") == data):
            self.write_atomic(path, data)
            changed = True
        tkeys = {self._wkey(w) for w in trusted}
        signed = [w for w in entries if self._wkey(w) in self._wsigned or self._wkey(w) in tkeys]
        key = self._key(True)
        rec = json.dumps({"entries": signed, "mac": self._wmac(key, signed)}, sort_keys=True) + "\n"
        rp = os.path.join(self._sd(), WIRING_RECORD)
        if not (os.path.lexists(rp) and _read_nofollow(rp, STATE_LIMITS["max_bytes"], "wiring record") == rec):
            self.write_atomic(rp, rec, mode=0o600)
        self._wsigned = {self._wkey(w) for w in signed}
        return changed

    # ── catalog ──
    def read_catalog(self):
        path = self.p("extensions.catalog.json") if self.state else None
        if not path or not os.path.lexists(path):
            return None
        try:
            cat = json_loads(_read_nofollow(path, 2 * 1024 * 1024, "catalog file"))
        except ValueError as ex:
            raise EngineError(EXIT_VERIFY, "imported catalog %s is corrupt (%s); re-import it with catalog <file>"
                              % (path, str(ex)[:80]))
        errs = _validate_catalog(cat)
        if errs:
            raise EngineError(EXIT_VERIFY, "imported catalog %s is invalid: %s" % (path, errs[0]))
        return cat

    def revoked(self, ext_id, version, digest=None):
        """The reason when the catalog revokes EXT_ID at VERSION or with content DIGEST, else None. Versions are
        compared by semver precedence (build metadata after '+' is ignored: 1.0.0+b2 is 1.0.0); an entry that
        carries a sha256 revokes exactly that content under that id, whatever version string it claims."""
        cat = self.read_catalog()
        if not cat:
            return None
        core = lambda v: v.split("+", 1)[0] if isinstance(v, str) else v
        for r in cat.get("revoked") or []:  # RULE:R9-revocation
            if r.get("id") != ext_id:
                continue
            if r.get("sha256"):  # RULE:R9-revoke-by-sha
                hit = digest is not None and r["sha256"] == digest
            else:
                hit = r.get("version") == "*" or core(r.get("version")) == core(version)  # RULE:R9-semver
            if hit:
                return r.get("reason") or "revoked by catalog"
        return None

    # ── safe deletes (R8) ──
    def rm_tree(self, path, allowed):
        if not os.path.lexists(path):
            return
        if not os.path.isfile(self.safe_rm):
            raise EngineError(EXIT_REFUSED, "scripts/lib/safe_rm.sh not found; refusing to delete %s" % path)
        env = dict(os.environ)
        env["SAFE_RM_ALLOWED_ROOTS"] = os.path.realpath(allowed)
        r = subprocess.run(["bash", "-c", '. "$1" && safe_rm_rf "$2"', "safe_rm", self.safe_rm, path],
                           env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        if r.returncode != 0 or os.path.lexists(path):
            raise EngineError(EXIT_FAIL, "safe_rm_rf refused or failed for %s: %s" % (path, r.stderr.strip()[:300]))

    # ── journal + recovery (R7, R12) ──
    def journal_problem(self, j):
        """None if J is a journal this engine could have written for this root, else the reason (R12)."""
        if not isinstance(j, dict):
            return "not a JSON object"
        op = j.get("op")
        if op == "wire":
            pid, ents = j.get("pid"), j.get("entries")
            if not isinstance(pid, int) or isinstance(pid, bool) or not 0 < pid <= 4194304 or not isinstance(ents, list) \
                    or len(ents) > 5000 or any(self._wiring_problem(w) for w in ents):  # RULE:R12-wire-journal
                return "malformed wire journal"
            return None
        if op == "commit":
            if not isinstance(j.get("records"), list) or not isinstance(j.get("deletes"), list) \
                    or any(not isinstance(i, str) or not ID_RE.match(i) for i in j["deletes"]):
                return "malformed commit journal"
            return None
        eid = j.get("id")
        if op not in ("add", "remove") or not isinstance(eid, str) or not ID_RE.match(eid):
            return "unknown op or invalid id"
        if j.get("final") != os.path.join(self.inst_dir, eid):  # RULE:R12-final-bound
            return "final path is not _installed/<id>"
        if op == "add" and not SHA256_RE.match(str(j.get("sha256", ""))):
            return "add journal without a sha256"
        if op in ("add", "remove"):  # RULE:F2-journal-mac: only this project's engine (holder of the state key) writes one
            try:
                key = self._key(False)
            except EngineError:
                key = None
            if key is None or not isinstance(j.get("mac"), str) \
                    or not hmac.compare_digest(j["mac"], self._jmac(key, j)):
                return "%s journal is unsigned or its signature does not verify (forged, or written by another checkout)" % op
        if op in ("add", "remove") and "ident" in j:  # RULE:R12-ident
            idt = j["ident"]
            if not isinstance(idt, list) or len(idt) != 3 or any(not isinstance(x, int) or isinstance(x, bool)
                                                                   for x in idt):
                return "add journal with a malformed object identity"
        if op == "remove":
            aux = j.get("aux")
            if not isinstance(aux, str) or os.path.dirname(aux) != self.inst_dir \
                    or not TRASH_RE.match(os.path.basename(aux)):  # RULE:R12-aux-bound
                return "aux path is not _installed/.trash-<pid>-<hex>"
        return None

    def _roll_records(self, recs, lock):
        key = self._key(False)
        for r in recs if isinstance(recs, list) else []:
            if self._record_valid(r, key) and lock.get(r["id"]) == r["entry"]:
                self.write_record(r)

    def recover(self, mutating=True):
        txn = self.p("extensions.txn")
        self._journal_bad = None
        j, why = None, None
        if os.path.lexists(txn):
            try:
                j = json_loads(_read_nofollow(txn, 4 * 1024 * 1024, "journal"))
            except (ValueError, EngineError):
                j = None
            why = self.journal_problem(j)
        if not mutating:  # RULE:I3-read-only-no-recovery
            if why:
                self._journal_bad = why
                self.err("WARNING: the journal %s is invalid (%s); a read-only command changes nothing. Inspect it, "
                         "then delete it; add/remove refuse while it is present." % (txn, why))
            elif j is not None:
                self.err("NOTE: an interrupted transaction is pending (journal %s); the next add, remove, enable, "
                         "disable, lock, catalog, wire or unwire recovers it. Nothing was changed." % txn)
            return
        if os.path.lexists(txn):
            try:
                j = json_loads(_read_nofollow(txn, 4 * 1024 * 1024, "journal"))
            except (ValueError, EngineError):
                j = None
            why = self.journal_problem(j)
            if why:
                self._journal_bad = why
                self.err("WARNING: ignored the journal %s (%s): nothing was rolled back or deleted. Inspect it, "
                         "then delete it; add/remove refuse while it is present." % (txn, why))
            else:
                if j.get("op") == "wire":
                    self._recover_wire(j)
                else:
                    self._recover_journal(j)
                os.unlink(txn)
        if self._journal_bad:  # RULE:I3-no-gc-with-bad-journal
            return
        if os.path.isdir(self.inst_dir):
            for n in sorted(os.listdir(self.inst_dir)):
                m = STAGING_RE.match(n)
                full = os.path.join(self.inst_dir, n)
                if m and stat.S_ISDIR(os.lstat(full).st_mode) and os.lstat(full).st_uid == os.geteuid():  # RULE:S1-sweep-owner
                    pid = int(m.group(2))
                    if pid == os.getpid() or _alive(pid):
                        continue
                    if m.group(1) == "trash":  # RULE:I3-trash-kept
                        # a trash directory may belong to another project's interrupted remove (the root can be
                        # shared); only the journal that names it may delete or restore it
                        self.err("NOTE: %s is left in place: no journal of this project names it (it may belong to "
                                 "another project's interrupted remove; that project's next command recovers it)"
                                 % full)
                        continue
                    self.rm_tree(full, self.inst_dir)
        for d in (self.state, self._sd()):
            if not os.path.isdir(d):
                continue
            for n in os.listdir(d):
                m = TMP_RE.match(n)
                if m and int(m.group(1)) <= 4194304 and not _alive(int(m.group(1))):
                    full = os.path.join(d, n)
                    st = os.lstat(full)
                    # RULE:M1-tmp-lstat: only a regular file or a link owned by this user is a temporary file of
                    # ours; a directory (or anything else) with such a name is left alone and reported
                    if (stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode)) and st.st_uid == os.geteuid():
                        os.unlink(full)
                    else:
                        self.err("NOTE: %s looks like a temporary file but is not a regular file or link owned by "
                                 "you; it was left in place" % full)
        top = self.p(SNAP_DIR)
        if os.path.isdir(top) and not os.path.islink(top):  # RULE:I2-stage-sweep
            for n in sorted(os.listdir(top)):
                m = SNAP_STAGE_RE.match(n)
                full = os.path.join(top, n)
                if not m or int(m.group(1)) > 4194304 or int(m.group(1)) == os.getpid() or _alive(int(m.group(1))):
                    continue
                st = os.lstat(full)
                if stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid():
                    self.rm_tree(full, top)
                    self.err("recovered: removed %s left by an interrupted wire" % full)

    def _recover_wire(self, j):
        """Remove the temporary shim files a crashed wire left next to the shims its journal names. Only an
        entry named <shim>.tmp-<the journal's pid>-<8 hex> whose process is gone, owned by this user, that is
        a link with an engine-computed text or a regular file carrying the managed-by marker is removed."""
        pid = j["pid"]
        if _alive(pid) or pid == os.getpid():  # RULE:M4-live-owner
            return
        proj = os.path.realpath(self.project)
        for w in j["entries"]:
            p = self._wabs(w["path"])
            d = os.path.dirname(p)
            if not os.path.isdir(d) or os.path.islink(d) or not _inside(os.path.realpath(d), proj):
                continue
            pat = re.compile(re.escape(os.path.basename(p)) + r"\.tmp-%d-[0-9a-f]{8}\Z" % pid)
            for n in sorted(os.listdir(d)):
                if not pat.match(n):
                    continue
                full = os.path.join(d, n)
                st = os.lstat(full)
                if os.geteuid() != st.st_uid:  # RULE:M4-owner
                    continue
                if stat.S_ISLNK(st.st_mode):
                    ok = os.readlink(full) in self._link_texts(w["id"], w["command"], w["path"], w.get("sha256"))
                else:
                    ok = stat.S_ISREG(st.st_mode) and self._marker_ok(w, full)
                if ok:  # RULE:M4-tmp-cleanup
                    os.unlink(full)
                    self.err("recovered: removed %s left by an interrupted wire" % full)
            dig = w.get("sha256")
            if w.get("agent") != "claude" or not isinstance(dig, str) or not SHA256_RE.match(dig):
                continue
            sd = os.path.dirname(self._snap(w["id"], w["command"], dig))
            if not os.path.isdir(sd) or os.path.islink(sd):
                continue
            spat = re.compile(re.escape(dig) + r"\.tmp-%d-[0-9a-f]{8}\Z" % pid)
            for n in sorted(os.listdir(sd)):
                full = os.path.join(sd, n)
                st = os.lstat(full)
                if spat.match(n) and stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid():  # RULE:I2-snap-tmp
                    self.rm_tree(full, os.path.join(self.state, SNAP_DIR))
                    self.err("recovered: removed %s left by an interrupted wire" % full)

    def _recover_journal(self, j):
        lock = self.read_lock()
        op, eid = j.get("op"), j.get("id")
        if op == "commit":
            self._roll_records(j.get("records"), lock)
            for i in j.get("deletes") or []:
                if i not in lock:
                    self.delete_record(i)
            return
        final = j["final"]
        if op == "add":
            if eid not in lock:  # RULE:R7-rollback
                if os.path.lexists(final):
                    # RULE:R12-own-object: the root can be shared by several projects; the tree at FINAL is
                    # removed only when it is the very directory this journal's add staged (device, inode and
                    # modification time survive the rename), never a tree another project installed since
                    if j.get("ident") is not None and _ident_of(final) == j["ident"]:
                        self.rm_tree(final, self.inst_dir)
                        self.err("recovered: rolled back interrupted add of %s" % eid)
                    else:
                        self.err("NOTE: %s was left in place: this project's journal cannot prove it created that "
                                 "tree (it may belong to another project that shares this constitution root)" % final)
            elif lock[eid].get("sha256") == j.get("sha256"):
                self._roll_records([j.get("record")], lock)
            else:
                self.err("WARNING: journal for %s disagrees with the lock (different sha256); left the tree alone" % eid)
        elif op == "remove":
            aux = j["aux"]
            # RULE:S1-own-aux: the trash directory is acted on (restored or deleted) only when it is PROVEN to be
            # the very tree this journal moved: both ends directly inside _installed, a trash name, a real
            # directory of this user, and the identity (device, inode, mtime) the remove recorded before the
            # rename. A trash-shaped directory the journal cannot prove (another project's, or an old journal
            # with no identity) is left in place and reported.
            owned = self._aux_owned(aux, final, j.get("ident"))
            if eid in lock:
                if os.path.lexists(aux) and not os.path.lexists(final):
                    if not owned:
                        self.err("WARNING: left %s alone: this journal cannot prove it is the tree it moved out of %s "
                                 "(it may belong to another project that shares this constitution root); %s was not "
                                 "restored" % (aux, final, eid))
                    else:
                        os.rename(aux, final)
                        self.err("recovered: rolled back interrupted remove of %s" % eid)
            else:
                if os.path.lexists(aux):
                    if owned:
                        self.rm_tree(aux, self.inst_dir)
                    else:
                        # RULE:D1-record-with-trash: the trash stays, and so does the state record beside it
                        self.err("WARNING: left %s alone: this journal cannot prove it is the tree it removed (it "
                                 "may belong to another project that shares this constitution root); delete it by "
                                 "hand if it is yours; the state record of %s was kept too" % (aux, eid))
                        return
                self.delete_record(eid)
                self.err("recovered: completed interrupted remove of %s" % eid)

    def _aux_owned(self, aux, final, ident):
        """True only when AUX is provably the directory a remove journal moved from FINAL (S1)."""
        if os.path.dirname(aux) != self.inst_dir or os.path.dirname(final) != self.inst_dir \
                or not TRASH_RE.match(os.path.basename(aux)):
            return False
        try:
            st = os.lstat(aux)
        except OSError:
            return False
        if not (stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid()):
            return False
        return isinstance(ident, list) and _ident_of(aux) == ident

    def _refuse_bad_journal(self):
        if self._journal_bad:
            raise EngineError(EXIT_REFUSED, "an invalid journal %s is present (%s); inspect and delete it first"
                              % (self.p("extensions.txn"), self._journal_bad))

    # ── extension discovery ──
    def tree_of(self, ext_id):
        b = os.path.join(self.ext_dir, ext_id)
        if os.path.isfile(os.path.join(b, "extension.yml")):
            return b, "bundled"
        i = os.path.join(self.inst_dir, ext_id)
        if os.path.isfile(os.path.join(i, "extension.yml")):
            return i, "installed"
        return None, None

    def discover(self):
        out = {}
        for base, origin in ((self.ext_dir, "bundled"), (self.inst_dir, "installed")):
            if not os.path.isdir(base):
                continue
            for n in sorted(os.listdir(base)):
                if n.startswith(("_", ".")) or not os.path.isfile(os.path.join(base, n, "extension.yml")):
                    continue
                if n in out:
                    continue
                out[n] = (os.path.join(base, n), origin)
        return out

    def load_manifest(self, tree):
        key = os.path.realpath(tree)
        if key in self._manifest_cache:
            return self._manifest_cache[key]
        p = os.path.join(tree, "extension.yml")
        st = os.lstat(p)
        if not stat.S_ISREG(st.st_mode):
            raise EngineError(EXIT_REFUSED, "extension.yml must be a regular file")
        if st.st_size > ext_yaml.MAX_BYTES:
            raise EngineError(EXIT_REFUSED, "extension.yml: document too large")
        try:
            with os.fdopen(_open_regular(p, "extension.yml"), "r", encoding="utf-8") as f:
                m = ext_yaml.parse(f.read(ext_yaml.MAX_BYTES + 1))
        except UnicodeDecodeError:
            raise EngineError(EXIT_REFUSED, "extension.yml: not UTF-8")
        except ext_yaml.YamlError as ex:
            raise EngineError(EXIT_REFUSED, "extension.yml: %s" % ex)
        errs = validate_manifest(m)
        if errs:
            raise EngineError(EXIT_REFUSED, "extension.yml invalid:\n  " + "\n  ".join(errs))
        self._manifest_cache[key] = m
        return m

    def tree_problems(self, tree, m):
        """Paths the manifest names must exist inside the tree as regular files."""
        errs = []
        prov = m.get("provides") or {}
        need = []
        for c in prov.get("commands") or []:
            need.append("commands/%s/SKILL.md" % c["name"])
        for s in prov.get("skills") or []:
            need.append(s["path"])
        for s in prov.get("mcp") or []:
            need.append(s["file"])
        for h in prov.get("hooks") or []:
            need.append(h["command"])
        for t in prov.get("templates") or []:
            need.append(t["file"])
        for x in (m.get("capabilities") or {}).get("executes") or []:
            need.append(x)
        rt = os.path.realpath(tree)
        for rel in need:
            full = os.path.realpath(os.path.join(tree, rel))
            if not full.startswith(rt + os.sep):
                errs.append("%s: escapes the extension root" % rel)
            elif not os.path.exists(os.path.join(tree, rel)):
                errs.append("%s: named in the manifest but missing" % rel)
        errs += content_problems(tree, m)  # R21, R22
        return errs

    def check_requirements(self, m, ext_id):
        errs = []
        req = m.get("requires") or {}
        cv = req.get("constitution_version")
        if cv:
            have = constitution_version(self.root)
            if have is None:
                errs.append("requires.constitution_version %s: constitution version UNKNOWN (no helixconstitution-v* tag)" % cv)
            elif not version_satisfies(have, cv):
                errs.append("requires.constitution_version %s: this constitution is %s" % (cv, have))
        known = self.discover()
        for r in req.get("extensions") or []:
            if r["id"] == ext_id or r["id"] not in known:
                errs.append("requires.extensions: %s is not available" % r["id"])
                continue
            if r.get("version"):
                try:
                    ver = self.load_manifest(known[r["id"]][0])["extension"]["version"]
                    if not version_satisfies(ver, r["version"]):
                        errs.append("requires.extensions: %s %s does not satisfy %s" % (r["id"], ver, r["version"]))
                except EngineError:
                    errs.append("requires.extensions: %s has an invalid manifest" % r["id"])
        for t in req.get("tools") or []:
            if t.get("required", True) and shutil.which(t["name"]) is None:
                errs.append("requires.tools: %s not found on PATH" % t["name"])
        anchors = req.get("anchors") or []
        if anchors:
            try:
                with open(os.path.join(self.root, "Constitution.md"), encoding="utf-8", errors="replace") as f:
                    text = f.read()
            except OSError:
                text = ""
            for a in anchors:
                if not re.search(re.escape("§" + a) + r"(?![0-9.])", text):
                    errs.append("requires.anchors: §%s not defined in Constitution.md" % a)
        for b in (m.get("provides") or {}).get("tools_bindings") or []:  # RULE:R10-binding
            if b["kind"] == "constitution-path":
                full = os.path.realpath(os.path.join(self.root, b["target"]))
                if not relpath_ok(b["target"]) or not full.startswith(os.path.realpath(self.root) + os.sep) \
                        or not os.path.isfile(full):
                    errs.append("provides.tools_bindings %s: target %s does not resolve inside the constitution" % (b["name"], b["target"]))
            else:
                if not TOOL_RE.match(b["target"]) or shutil.which(b["target"]) is None:
                    errs.append("provides.tools_bindings %s: command %s not found on PATH" % (b["name"], b["target"]))
        return errs

    def command_owners(self, skip_id=None):
        owners = {}
        for eid, (tree, _o) in sorted(self.discover().items()):
            if eid == skip_id:
                continue
            try:
                m = self.load_manifest(tree)
            except EngineError:
                continue
            for c in (m.get("provides") or {}).get("commands") or []:
                owners[c["name"]] = eid
        return owners

    # ── consent (R5) ──
    CAP_NOTES = (("agent-shell:", "the agent runs shell commands written in this command's text when it is invoked"),
                 ("reads-files:", "the agent reads files named in this command's text into the prompt"),
                 ("shell:", "this MCP server is started through a shell or with inline code"),
                 ("mcp-command:", "the exact program and arguments an MCP client starts"),
                 ("env-code:", "this variable can make the program load or run other code"),
                 ("mcp-dir:", "the working directory or environment file an MCP client uses"),
                 ("tree-sha256:", "everything a hook, MCP server or program of this extension can load is part of "
                                  "the consent; any change to the tree needs a new consent"),
                 ("sha256:", "the content of this file is part of the consent; any change needs a new consent"))

    def consent(self, ext_id, caps, action, tier="community", waiver=None):
        # always shown, on stderr, so --json output cannot hide what is being granted
        lines = ["Capabilities requested by %s (%s):" % (ext_id, action),
                 "  trust tier: %s" % disp(tier or "community"), "  waiver id: %s" % disp(waiver or "none")]
        for c in caps or ["(none)"]:
            note = "".join("  (%s)" % t for pfx, t in self.CAP_NOTES if c.startswith(pfx))
            lines.append("  - " + disp(c) + note)
        for ln in lines:
            print(ln, file=sys.stderr)  # RULE:R5-consent-visible
        if self.o["yes"]:
            return "yes"
        if os.environ.get("CONSTITUTION_EXT_NO_TTY") == "1":
            raise EngineError(EXIT_REFUSED, "consent required: pass --yes or run interactively")
        try:  # unbuffered binary I/O: a text-mode "r+" open of a terminal fails ("not seekable")
            tty = open(os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY), "r+b", buffering=0)
        except OSError:
            raise EngineError(EXIT_REFUSED, "consent required: pass --yes or run interactively")
        with tty:
            tty.write(("\n".join(lines) + "\n").encode("utf-8", "replace"))
            tty.write(("Grant these capabilities and %s %s? [y/N] " % (action, ext_id)).encode())
            ans = tty.readline(64).decode("utf-8", "replace").strip().lower()
        if ans not in ("y", "yes"):
            raise EngineError(EXIT_REFUSED, "consent declined")
        return "tty"

    def ensure_exclude(self):
        r = _git(["-C", self.root, "rev-parse", "--show-toplevel"])
        if r.returncode != 0:
            return
        top = os.path.realpath(r.stdout.strip())
        rel = os.path.relpath(os.path.realpath(self.inst_dir), top)
        pat = "extensions/_installed/" if rel == "extensions/_installed" else "/" + rel + "/"
        g = _git(["-C", self.root, "rev-parse", "--git-path", "info/exclude"])
        if g.returncode != 0:
            return
        ex = g.stdout.strip()
        if not os.path.isabs(ex):
            ex = os.path.join(self.root, ex)
        text = _read_nofollow(ex, 1 << 20, ex) if os.path.lexists(ex) else ""
        if pat in text.splitlines():
            return
        os.makedirs(os.path.dirname(ex), exist_ok=True)
        fd = os.open(ex, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(("\n" if text and not text.endswith("\n") else "") + pat + "\n")

    # ═════════════════════════════ commands ═════════════════════════════
    def cmd_validate(self, path):
        res = {"ok": False, "path": path, "errors": []}
        if not os.path.isdir(path) or not os.path.isfile(os.path.join(path, "extension.yml")):
            res["errors"] = ["%s: not an extension directory (no extension.yml)" % path]
        else:
            errs = check_tree(path, skip_git=True)
            m = None
            try:
                m = self.load_manifest(path)
            except EngineError as ex:
                errs.append(ex.msg)
            if m is not None:
                errs += self.tree_problems(path, m)
                res["id"] = m["extension"]["id"]
                res["version"] = m["extension"]["version"]
                res["capabilities"] = capabilities_of(m, path, skip_git=True)
            if os.path.isfile(os.path.join(path, CHECKSUMS)):
                try:
                    with os.fdopen(_open_regular(os.path.join(path, CHECKSUMS), CHECKSUMS), "r", encoding="utf-8") as f:
                        if parse_checksums(f.read()) != file_hashes(path, skip_git=True):
                            errs.append("%s does not match the tree" % CHECKSUMS)
                except EngineError as ex:
                    errs.append(ex.msg)
            if not errs:
                res["sha256"] = tree_digest(path, skip_git=True)
            res["errors"] = errs
            res["ok"] = not errs
        if self.json:
            print(json.dumps(res, sort_keys=True, indent=2))
        elif res["ok"]:
            print("OK %s %s sha256=%s" % (res["id"], res["version"], res["sha256"]))
        else:
            print("INVALID %s" % path)
            for e in res["errors"]:
                print("  " + e)
        return EXIT_OK if res["ok"] else EXIT_FAIL

    def _row(self, eid, tree, origin, lock):
        e = lock.get(eid)
        row = {"id": eid, "origin": origin, "enabled": bool(e and e.get("enabled")), "status": "ok"}
        if tree is None:
            row.update({"origin": e.get("origin"), "status": "missing", "version": e.get("version")})
            return row
        try:
            m = self.load_manifest(tree)
            row["version"] = m["extension"]["version"]
            if m["extension"]["id"] != eid:
                row["status"] = "invalid"
        except EngineError:
            row["status"] = "invalid"
            row["version"] = None
        if origin == "installed" and not e:
            row["status"] = "untracked"
        return row

    def cmd_list(self):
        self.acquire(False)
        lock = self.read_lock()
        found = self.discover()
        rows = [self._row(i, found[i][0], found[i][1], lock) for i in sorted(found)]
        rows += [self._row(i, None, None, lock) for i in sorted(lock) if i not in found]
        rows.sort(key=lambda r: r["id"])
        if self.json:
            print(json.dumps({"extensions": rows}, sort_keys=True, indent=2))
        elif not rows:
            print("no extensions (bundled: %s, installed: %s)" % (self.ext_dir, self.inst_dir))
        else:
            for r in rows:
                print("%-32s %-12s %-10s %-8s %s" % (r["id"], r.get("version") or "-", r["origin"] or "-",
                                                   "enabled" if r["enabled"] else "disabled", r["status"]))
        return EXIT_OK

    def _components(self, m, enabled):
        prov = m.get("provides") or {}
        comp = {}
        for k in ("hooks", "mcp"):
            comp[k] = ("enabled" if enabled else "disabled") if prov.get(k) else "none"
        return comp

    def cmd_info(self, eid):
        self.acquire(False)
        tree, origin = self.tree_of(eid)
        lock = self.read_lock()
        if tree is None and eid not in lock:
            raise EngineError(EXIT_FAIL, "%s: no such extension" % eid)
        e = lock.get(eid) or {}
        res = {"id": eid, "origin": origin or e.get("origin"), "enabled": bool(e.get("enabled")),
               "path": tree, "lock": e or None,
               "wired": [w for w in self.read_wiring() if w.get("id") == eid]}
        if tree:
            m = self.load_manifest(tree)
            x = m["extension"]
            res.update({"version": x["version"], "name": x["name"], "description": x["description"],
                        "trust_tier": "builtin" if origin == "bundled" else (e.get("trust_tier") or "community"),
                        "commands": [c["name"] for c in (m.get("provides") or {}).get("commands") or []],
                        "capabilities": capabilities_of(m, tree), "requires": m.get("requires") or {},
                        "compatibility": m.get("compatibility") or {},
                        "components": self._components(m, res["enabled"])})
        else:
            res.update({"version": e.get("version"), "status": "missing"})
        if self.json:
            print(json.dumps(res, sort_keys=True, indent=2))
        else:
            for k in ("id", "version", "origin", "enabled", "path", "trust_tier", "commands", "components",
                      "capabilities", "compatibility"):
                if k in res:
                    print("%-14s %s" % (k + ":", res[k]))
            if e:
                print("%-14s %s" % ("sha256:", e.get("sha256")))
                print("%-14s %s" % ("source:", e.get("source")))
        return EXIT_OK

    def _resolve_catalog_source(self, src):
        cat = self.read_catalog()
        if not cat or src not in (cat.get("extensions") or {}):
            return None
        if not (cat.get("catalog") or {}).get("install_allowed"):
            raise EngineError(EXIT_REFUSED, "catalog %s is discovery-only (install_allowed: false)" % (cat.get("catalog") or {}).get("id"))
        ent = cat["extensions"][src]
        rels = ent.get("releases") or {}
        ver = ent.get("latest") or (sorted(rels, key=_vtuple)[-1] if rels else None)
        if not ver or ver not in rels:
            raise EngineError(EXIT_REFUSED, "catalog has no installable release for %s" % src)
        r = rels[ver]
        return r["url"], r.get("git_sha"), r["sha256"], (cat.get("catalog") or {}).get("trust_tier", "community")

    def cmd_add(self, src):
        self.need_project()
        o = self.o
        sha, sha256, waiver = o.get("sha"), o.get("sha256"), o.get("waiver_id")
        if src.startswith("-"):
            raise EngineError(EXIT_USAGE, "source must not start with '-'")
        if bad_chars(src):
            raise EngineError(EXIT_REFUSED, "source contains control, bidi/format or separator characters")
        # R13: the exclusive lock is held for the WHOLE add, so every check below is made under it
        self.acquire(False, mutating=True)
        self._refuse_bad_journal()
        self._tier = "community"
        if not os.path.exists(src) and ID_RE.match(src) and self.state:
            got = self._resolve_catalog_source(src)
            if got:
                src, sha, sha256, self._tier = got[0], sha or got[1], sha256 or got[2], got[3]
        local = os.path.isdir(src)
        if local and (o["dev"] or not os.path.exists(os.path.join(src, ".git"))):
            kind = "dir"
            if looks_secret(os.path.abspath(src)):
                raise EngineError(EXIT_REFUSED, "source path contains a secret-looking value (value withheld)")
        else:
            kind = "git"
            if not local:
                why = url_problem(src)
                if why:
                    raise EngineError(EXIT_REFUSED, "source: %s" % why)
        # R4: pins
        if kind == "git" and not sha and not waiver:  # RULE:R4-git-pin
            raise EngineError(EXIT_REFUSED, "unpinned git source: pass --sha <40-hex commit> or record a waiver with --waiver-id ID (§11.4.271)")
        if kind == "git" and sha and not sha256 and not waiver:  # RULE:R4-git-content-pin
            raise EngineError(EXIT_REFUSED, "a pinned git source needs the content digest too: pass --sha256 <tree digest> "
                                            "(shown by validate) next to --sha, or record a waiver with --waiver-id ID")
        if kind == "dir" and not sha256 and not waiver:  # RULE:R4-dir-pin
            raise EngineError(EXIT_REFUSED, "unpinned local source: pass --sha256 <tree digest> or record a waiver with --waiver-id ID (§11.4.271)")
        if kind == "dir" and sha:
            raise EngineError(EXIT_USAGE, "--sha applies to git sources; use --sha256 for a directory")
        self._work = None
        try:
            if kind == "git" and not self.dry:
                self._make_work()
            return self._add(src, kind, sha, sha256, waiver)
        finally:
            if self._work and os.path.lexists(self._work):
                self.rm_tree(self._work, self.inst_dir)

    def _make_work(self):
        """Staging dir inside _installed (same filesystem, so the final rename is atomic)."""
        if self._work is None:
            os.makedirs(self.inst_dir, exist_ok=True)
            self.ensure_exclude()
            self._work = os.path.join(self.inst_dir, ".staging-%d-%s" % (os.getpid(), os.urandom(4).hex()))
            os.mkdir(self._work, 0o700)
        return self._work

    def _add(self, src, kind, sha, sha256, waiver):
        resolved_sha = None
        work = self._work
        if kind == "git":
            if work is None:
                raise EngineError(EXIT_OK, "dry-run: would clone %s at %s and install it" % (redact(src), sha or "HEAD (waiver)"))
            clone = os.path.join(work, "src")
            r = _git(["clone", "--quiet", "--no-checkout", "--no-recurse-submodules", "--", src, clone])
            if r.returncode != 0:
                raise EngineError(EXIT_FAIL, "git clone failed: %s" % redact(r.stderr.strip()[:300]))
            _harden_clone(clone)
            if sha:
                if _git(["-C", clone, "cat-file", "-e", sha + "^{commit}"]).returncode != 0:
                    raise EngineError(EXIT_VERIFY, "pinned commit %s not found in the source" % sha)
                resolved_sha = sha
            else:
                resolved_sha = _git(["-C", clone, "rev-parse", "HEAD"], check=True).stdout.strip()
            gerr = _git_tree_problems(clone, resolved_sha)
            if gerr:
                raise EngineError(EXIT_REFUSED, "extension tree rejected:\n  " + "\n  ".join(gerr))
            _git(["-C", clone, "checkout", "--quiet", "--detach", resolved_sha, "--"], check=True)
            self.rm_tree(os.path.join(clone, ".git"), work)  # B4: metadata removed only after checkout
            srcdir = clone
        else:
            srcdir = os.path.abspath(src)
        if not os.path.isfile(os.path.join(srcdir, "extension.yml")):
            raise EngineError(EXIT_REFUSED, "no extension.yml at the source root")
        terrs = check_tree(srcdir)
        if terrs:
            raise EngineError(EXIT_REFUSED, "extension tree rejected:\n  " + "\n  ".join(terrs))
        m = self.load_manifest(srcdir)
        x = m["extension"]
        eid, ver = x["id"], x["version"]
        perr = self.tree_problems(srcdir, m)
        if perr:
            raise EngineError(EXIT_REFUSED, "extension tree incomplete:\n  " + "\n  ".join(perr))
        msrc = x.get("source") or {}
        if kind == "git" and msrc.get("sha") and msrc["sha"] != resolved_sha:
            raise EngineError(EXIT_VERIFY, "manifest source.sha does not match the fetched commit")
        hashes = file_hashes(srcdir)
        if os.path.isfile(os.path.join(srcdir, CHECKSUMS)):
            if parse_checksums(_read_nofollow(os.path.join(srcdir, CHECKSUMS), MAX_FILE_BYTES, CHECKSUMS)) != hashes:  # RULE:R7-source-checksums
                raise EngineError(EXIT_VERIFY, "%s in the source does not match its files" % CHECKSUMS)
        digest = hashlib.sha256(checksums_text(hashes).encode()).hexdigest()
        if sha256 and sha256 != digest:  # RULE:R4-sha256
            raise EngineError(EXIT_VERIFY, "content sha256 mismatch: expected %s, got %s" % (sha256, digest))
        if msrc.get("sha256") and msrc["sha256"] != digest:
            raise EngineError(EXIT_VERIFY, "manifest source.sha256 does not match the content")
        why = self.revoked(eid, ver, digest)
        if why:
            raise EngineError(EXIT_REFUSED, "%s %s is revoked by the catalog: %s" % (eid, ver, disp(why)))
        lock = self.read_lock()
        btree, borigin = self.tree_of(eid)
        if borigin == "bundled":
            raise EngineError(EXIT_REFUSED, "%s is a bundled extension; use enable/disable" % eid)
        if borigin == "installed" or os.path.lexists(os.path.join(self.inst_dir, eid)):
            if borigin == "installed" and eid in lock and lock[eid].get("sha256") == digest:
                self.say("%s %s already installed (sha256 %s); nothing to do" % (eid, ver, digest))
                return EXIT_OK
            raise EngineError(EXIT_REFUSED, "%s is already present in the shared constitution root and %s; this project "
                                            "does not replace it (remove only works on an id in this project's lock)"
                                  % (eid, "is not in this project's lock" if eid not in lock else "has different content"))
        rerrs = self.check_requirements(m, eid)
        owners = self.command_owners(skip_id=eid)
        for c in (m.get("provides") or {}).get("commands") or []:
            if c["name"] in owners:
                rerrs.append("command %s already provided by %s" % (c["name"], owners[c["name"]]))
        if rerrs:
            raise EngineError(EXIT_REFUSED, "requirements not met:\n  " + "\n  ".join(rerrs))
        caps = capabilities_of(m, srcdir)
        if self.dry:
            self.say("dry-run: would install %s %s (sha256 %s) to %s with capabilities: %s"
                     % (eid, ver, digest, os.path.join(self.inst_dir, eid), ", ".join(disp(c) for c in caps) or "(none)"))
            return EXIT_OK
        mode = self.consent(eid, caps, "install", self._tier, waiver)
        self.ensure_state()
        work = self._make_work()
        # stage (R1: copy only)
        staged = os.path.join(work, "tree")
        _copy_tree(srcdir, staged, False)
        fd = os.open(os.path.join(staged, CHECKSUMS), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(checksums_text(hashes))
        kill_point("add:staged")
        if tree_digest(staged) != digest:  # RULE:R7-staged-verify
            raise EngineError(EXIT_VERIFY, "staged copy does not match the source digest")
        kill_point("add:checked")
        final = os.path.join(self.inst_dir, eid)
        base = "url"
        location = src
        if kind == "dir" or os.path.isdir(src):
            absp, proj = os.path.realpath(src), os.path.realpath(self.project)
            if _inside(absp, proj) and absp != proj:  # portable: recorded relative to the project
                base, location = "project", os.path.relpath(absp, proj)
            else:
                base, location = "absolute", os.path.abspath(src)
        if looks_secret(location):
            raise EngineError(EXIT_REFUSED, "refusing to record a secret-looking source location in the lock")
        entry = {"id": eid, "version": ver, "origin": "installed", "sha256": digest, "enabled": False,
                 "dev": bool(self.o["dev"]), "waiver_id": waiver, "trust_tier": self._tier,
                 "source": {"kind": kind, "location": location, "base": base, "sha": resolved_sha},
                 "consent": {"capabilities": caps, "mode": mode},
                 "components": self._components(m, False)}
        rec = self.make_record(eid, entry)
        jadd = {"op": "add", "id": eid, "final": final, "sha256": digest, "record": rec, "ident": _ident_of(staged)}
        jadd["mac"] = self._jmac(self._key(True), jadd)  # RULE:F2-journal-mac
        self.write_atomic(self.p("extensions.txn"), json.dumps(jadd))
        kill_point("add:journaled")
        try:
            os.rename(staged, final)
        except OSError as ex:
            os.unlink(self.p("extensions.txn"))
            raise EngineError(EXIT_FAIL, "cannot move the staged tree into place (%s)" % ex.strerror)
        kill_point("add:renamed")
        lock[eid] = entry
        self.commit(lock, [eid], outer=True)
        kill_point("add:locked")
        os.unlink(self.p("extensions.txn"))
        if tree_digest(final) != digest:  # RULE:R7-verify-after-install (§11.4.200)
            raise EngineError(EXIT_VERIFY, "installed tree does not verify; run remove %s" % eid)
        self.audit("add", eid, "sha256=%s waiver=%s" % (digest, waiver or ""))
        self.say("installed %s %s (disabled; run enable %s)" % (eid, ver, eid))
        return EXIT_OK

    def cmd_remove(self, eid):
        self.need_project()
        self.acquire(True)
        tree, origin = self.tree_of(eid)
        if origin == "bundled":
            raise EngineError(EXIT_REFUSED, "%s is bundled with the constitution; use disable" % eid)
        lock = self.read_lock()
        if tree is None and eid not in lock:
            raise EngineError(EXIT_FAIL, "%s: not installed" % eid)
        if eid not in lock:  # RULE:F1-lock-membership: the root is shared; a tree no lock of ours names is not ours
            raise EngineError(EXIT_REFUSED, "%s is not in this project's lock, so this project cannot prove it "
                                            "installed %s (it may belong to another project that shares this "
                                            "constitution root); nothing was removed" % (eid, os.path.join(self.inst_dir, eid)))
        # RULE:F3-own-record: the lock is committed, so a project can hold a COPY of another project's lock; only
        # the local HMAC-signed state record (never committed, keyed by this checkout's own key) proves THIS
        # project installed the id. Without it nothing is removed. Not detected (documented): whether another
        # project's wiring still points at the shared tree; that needs a registry of projects the root lacks.
        if [x for x in self.record_problems(eid, lock[eid]) if not x.startswith("lock field")]:
            raise EngineError(EXIT_REFUSED, "%s: this checkout has no valid signed state record for it, so this "
                                            "project cannot prove it installed %s (the lock may be a copy of "
                                            "another project's); nothing was removed" % (eid, os.path.join(self.inst_dir, eid)))
        if self.dry:
            self.say("dry-run: would unwire and remove %s" % eid)
            return EXIT_OK
        self._refuse_bad_journal()
        self._unwire(eid, WIRE_AGENTS, None)
        final = os.path.join(self.inst_dir, eid)
        trash = os.path.join(self.inst_dir, ".trash-%d-%s" % (os.getpid(), os.urandom(4).hex()))
        # RULE:F1-tree-pinned: the tree is moved only when it is the very content this project's lock pinned. A
        # different tree under the same id was put there by another project (or tampered with); the lock entry is
        # still dropped, the tree is left in place and reported.
        mine = False
        if os.path.lexists(final) and not os.path.islink(final):
            try:
                mine = tree_digest(final) == lock[eid].get("sha256")
            except EngineError:
                mine = False
        jr = {"op": "remove", "id": eid, "final": final, "aux": trash}
        if mine and _ident_of(final) is not None:  # RULE:S1-ident: survives the rename
            jr["ident"] = _ident_of(final)
        jr["mac"] = self._jmac(self._key(True), jr)  # RULE:F4-remove-journal-mac
        self.write_atomic(self.p("extensions.txn"), json.dumps(jr))
        kill_point("remove:journaled")
        if os.path.lexists(final) and not mine:
            self.err("NOTE: %s was left in place: its content is not the one this project's lock pinned (it may "
                     "belong to another project that shares this constitution root, or was modified); only this "
                     "project's lock entry was removed. Delete the directory by hand if it is yours." % final)
        if mine:
            os.rename(final, trash)
        kill_point("remove:trashed")
        lock.pop(eid, None)
        self.commit(lock, [eid], outer=True)
        kill_point("remove:locked")
        self.rm_tree(trash, self.inst_dir)
        os.unlink(self.p("extensions.txn"))
        self.audit("remove", eid)
        self.say("removed %s" % eid)
        return EXIT_OK

    def _entry_for(self, eid, lock, refresh_bundled=False):
        """(tree, manifest, lock entry). A tree that differs from its lock entry is refused, except that
        REFRESH_BUNDLED (enable, which then asks for consent again) returns a bundled entry with the new
        sha256 and version: a constitution update may change a bundled extension (I3)."""
        tree, origin = self.tree_of(eid)
        if tree is None:
            if (lock.get(eid) or {}).get("origin") == "installed":
                raise EngineError(EXIT_FAIL, "%s: the installed tree %s is not present in this checkout "
                                             "(extensions/_installed/ is git-ignored; a clone never has it): run verify "
                                             "for the add command that reinstalls it with the lock's pins, or remove %s"
                                  % (eid, os.path.join(self.inst_dir, eid), eid))
            raise EngineError(EXIT_FAIL, "%s: no such extension" % eid)
        m = self.load_manifest(tree)
        digest = tree_digest(tree)
        e = lock.get(eid)
        if e is None:
            if origin != "bundled":
                raise EngineError(EXIT_REFUSED, "%s is installed but not in this project's lock (untracked; it may belong to another project that shares this constitution root): add it to this project, or delete the directory by hand" % eid)
            e = {"id": eid, "version": m["extension"]["version"], "origin": "bundled", "sha256": digest,
                 "enabled": False, "dev": False, "waiver_id": None,
                 "source": {"kind": "bundled", "location": "extensions/" + eid, "sha": None},
                 "consent": {"capabilities": [], "mode": "none"}, "components": self._components(m, False)}
        elif e.get("sha256") != digest and refresh_bundled and origin == "bundled" and e.get("origin") == "bundled":
            e = dict(e)
            e["sha256"], e["version"] = digest, m["extension"]["version"]
        elif e.get("sha256") != digest:
            raise EngineError(EXIT_VERIFY, "%s: tree does not match the lock (sha256 %s, lock %s); run verify" % (eid, digest, e.get("sha256")))
        return tree, m, e

    def cmd_enable(self, eid):
        self.need_project()
        self.acquire(True)
        lock = self.read_lock()
        tree, m, e = self._entry_for(eid, lock, refresh_bundled=True)
        why = self.revoked(eid, m["extension"]["version"], e.get("sha256"))
        if why:  # RULE:R9-enable-revocation
            raise EngineError(EXIT_REFUSED, "%s is revoked by the catalog: %s" % (eid, disp(why)))
        cerr = content_problems(tree, m)
        if cerr:  # RULE:R21-enable
            raise EngineError(EXIT_REFUSED, "%s: undeclared agent-side constructs or unsafe MCP commands:\n  %s"
                              % (eid, "\n  ".join(cerr)))
        caps = capabilities_of(m, tree)
        rp = self.record_problems(eid, lock[eid]) if eid in lock else []
        missing = bool(rp) and rp[0].startswith("no local state record")
        if rp and not missing:  # RULE:R17-enable-check
            raise EngineError(EXIT_VERIFY, "%s: refusing to enable over a tampered lock entry:\n  %s" % (eid, "\n  ".join(rp)))
        if e.get("enabled") and (e.get("consent") or {}).get("capabilities") == caps and not rp \
                and e == lock.get(eid):
            self.say("%s already enabled" % eid)
            return EXIT_OK
        if self.dry:
            self.say("dry-run: would enable %s with capabilities: %s" % (eid, ", ".join(disp(c) for c in caps) or "(none)"))
            return EXIT_OK
        tier = "builtin" if e.get("origin") == "bundled" else (e.get("trust_tier") or "community")
        mode = self.consent(eid, caps, "enable", tier, e.get("waiver_id"))  # RULE:R5-consent-enable
        e = dict(e)
        e.update({"enabled": True, "consent": {"capabilities": caps, "mode": mode},
                  "components": self._components(m, True)})
        lock[eid] = e
        self.commit(lock, [eid], stage="enable:locked")
        self.audit("enable", eid)
        self.say("enabled %s (hooks/MCP marked enabled in the lock; commands materialise with wire)" % eid)
        return EXIT_OK

    def cmd_disable(self, eid):
        self.need_project()
        self.acquire(True)
        lock = self.read_lock()
        tree, origin = self.tree_of(eid)
        if tree is None and eid not in lock:
            raise EngineError(EXIT_FAIL, "%s: no such extension" % eid)
        e = lock.get(eid)
        has_wire = any(w.get("id") == eid for w in self.read_wiring())
        if (not e or not e.get("enabled")) and not has_wire:
            self.say("%s already disabled" % eid)
            return EXIT_OK
        if self.dry:
            self.say("dry-run: would unwire and disable %s" % eid)
            return EXIT_OK
        self._unwire(eid, WIRE_AGENTS, None)
        if e:
            clean = not self.record_problems(eid, e)
            e = dict(e)
            comp = e.get("components") or {}
            e["enabled"] = False
            e["components"] = {k: ("disabled" if v == "enabled" else v) for k, v in comp.items()}
            lock[eid] = e
            if clean:
                self.commit(lock, [eid], stage="disable:locked")
            else:  # never launder a tampered entry into a fresh signed record
                self.write_lock(lock, stage="disable:locked")
                self.err("%s: lock entry does not match the local state record; disabled in the lock only "
                         "(verify will keep reporting it)" % eid)
        self.audit("disable", eid)
        self.say("disabled %s" % eid)
        return EXIT_OK

    def verify_one(self, eid, e):
        probs = []
        tree, origin = self.tree_of(eid)
        if tree is None:
            nw = sum(1 for w in self.read_wiring() if w["id"] == eid)
            if e.get("origin") == "installed":
                src = e.get("source") if isinstance(e.get("source"), dict) else {}
                if e.get("waiver_id"):
                    pins = "--waiver-id %s" % disp(e.get("waiver_id"))
                elif src.get("sha"):
                    pins = "--sha %s --sha256 %s" % (disp(src.get("sha")), disp(e.get("sha256")))
                else:
                    pins = "--sha256 %s" % disp(e.get("sha256"))
                shims = (" %d wired shim(s) point at the missing tree (unwire or disable removes them)." % nw) if nw else ""
                return ["tree missing: %s is not present in this checkout (extensions/_installed/ is git-ignored, so "
                        "a clone or a fresh checkout never has it). Reinstall it with the lock's pins: add %s %s, "
                        "or drop it with remove %s.%s"
                        % (os.path.join(self.inst_dir, eid), redact(src.get("location") or "<source>"), pins, eid, shims)]
            return ["tree missing: %s (the bundled extension is no longer shipped by this constitution; disable %s)"
                    % (os.path.join(self.ext_dir, eid), eid)]
        try:
            m = self.load_manifest(tree)
        except EngineError as ex:
            return [ex.msg]
        if m["extension"]["version"] != e.get("version"):
            probs.append("version %s differs from lock %s" % (m["extension"]["version"], disp(e.get("version"))))
        terrs = check_tree(tree)
        probs += terrs
        hashes = file_hashes(tree)
        cpath = os.path.join(tree, CHECKSUMS)
        if origin == "installed":
            try:
                recorded = parse_checksums(_read_nofollow(cpath, MAX_FILE_BYTES, CHECKSUMS))
            except (OSError, EngineError):
                recorded = None
            if recorded is None:
                probs.append("%s missing or malformed" % CHECKSUMS)
            else:
                for r in sorted(set(recorded) | set(hashes)):
                    if r not in hashes:
                        probs.append("%s: missing" % r)
                    elif r not in recorded:
                        probs.append("%s: not in %s (added after install)" % (r, CHECKSUMS))
                    elif recorded[r] != hashes[r]:
                        probs.append("%s: content changed" % r)
        digest = hashlib.sha256(checksums_text(hashes).encode()).hexdigest()
        if digest != e.get("sha256"):  # RULE:R7-verify-digest
            probs.append("tree sha256 %s differs from lock %s%s" % (digest, disp(e.get("sha256")),
                                                                    " (bundled: run lock after a constitution update)" if origin == "bundled" else ""))
        why = self.revoked(eid, m["extension"]["version"], digest)
        if why:
            probs.append("revoked by catalog: %s" % disp(why))
        try:
            now = capabilities_of(m, tree)
        except EngineError as ex:
            now = None
            probs.append(ex.msg)
        if e.get("enabled") and (e.get("consent") or {}).get("capabilities") != now:
            probs.append("capabilities changed since consent (the list or the content it binds; review and "
                         "grant them again with: enable %s)" % eid)
        probs += content_problems(tree, m)
        want = self._components(m, bool(e.get("enabled")))
        if (e.get("components") or {}) != want:  # RULE:R5-components-consistent
            probs.append("lock components %s disagree with enabled=%s (expected %s)"
                         % (disp(e.get("components")), bool(e.get("enabled")), want))
        probs += self.record_problems(eid, e)
        for w in self.read_wiring():
            if w.get("id") != eid:
                continue
            probs += self._wiring_derived_problems(w, m, hashes, tree)
        return probs

    def _wiring_derived_problems(self, w, m, hashes, tree):
        """I2: everything a wiring entry claims is re-derived from the LOCKED tree's per-file hashes (HASHES,
        read just now) and from the manifest, never taken from the values stored in the wiring file: the digest of
        the command, the link text, the snapshot's files (hash, listing and the R21 scan), the text a non-Claude
        shim must have. A wiring file edited to agree with a forged shim therefore fails here."""
        probs = []
        p = self._wabs(w["path"])
        cmd = w["command"]
        names = {c["name"]: c for c in (m.get("provides") or {}).get("commands") or []}
        if cmd not in names:
            return ["wired command %s is not a command of %s any more (unwire it)" % (disp(cmd), w["id"])]
        if w.get("kind") == "symlink":
            if w.get("sha256") is None:  # RULE:I2-legacy-link
                if not os.path.islink(p) or os.readlink(p) != w.get("target"):
                    return ["wired link %s changed or missing" % p]
                return ["wired link %s points into the live extension tree (old format: a content change "
                        "reaches the agent without a new consent); run wire again" % p]
            want = command_digest_of(hashes, "commands/%s/" % cmd)
            if w["sha256"] != want:  # RULE:I2-wiring-digest-derived
                probs.append("wiring entry for %s records snapshot digest %s but the locked tree's command has %s "
                             "(the command changed since it was wired, or the wiring file was edited; unwire, then "
                             "wire again)" % (p, w["sha256"][:12], want[:12]))
            want_link = self._link_texts(w["id"], cmd, w["path"], want)[0]
            if not os.path.islink(p) or os.readlink(p) != want_link:  # RULE:I2-link-derived
                probs.append("wired link %s changed or missing (expected a link to the snapshot of the locked "
                             "command)" % p)
            snap = self._snap(w["id"], cmd, want)
            try:
                good = not os.path.islink(snap) and os.path.isdir(snap) and command_digest(snap) == want
            except EngineError:
                good = False
            if not good:  # RULE:I2-snap-verify
                probs.append("wired snapshot %s changed or missing (unwire, then wire again)" % snap)
            else:  # RULE:I2-snap-rescan: the snapshot is what the agent reads, so it is scanned again
                decl = decl_of(m)
                for dp, dns, fns in os.walk(snap, onerror=_walk_error):
                    dns.sort()
                    for n in sorted(fns):
                        full = os.path.join(dp, n)
                        probs += file_construct_problems("snapshot %s/%s" % (cmd, os.path.relpath(full, snap)), full,
                                                         cmd, decl)
            return probs
        # a file shim (opencode, pi, gemini, qwen): re-render from the locked tree and compare
        try:
            text = _read_nofollow(os.path.join(tree, "commands", cmd, "SKILL.md"), MAX_FILE_BYTES, "SKILL.md")
            want_text = self._render_text(w["agent"], w["id"], cmd, text, names[cmd]["description"], "SKILL.md")
        except EngineError as ex:
            return ["wired file %s cannot be re-derived from the locked command (%s)" % (p, ex.msg)]
        want_sha = hashlib.sha256(want_text.encode()).hexdigest()
        if not _is_reg(p):
            return ["wired file %s changed or missing" % p]
        if _sha_file(p) != want_sha:  # RULE:I2-shim-rerender
            probs.append("wired file %s differs from the shim rendered from the locked command (edited, or the "
                         "command changed since wiring)" % p)
        if w.get("sha256") != want_sha:
            probs.append("wiring entry for %s records sha256 %s, not the rendered shim's %s" % (p, w.get("sha256"), want_sha[:12]))
        rerr = self._rendered_problems(m, w["agent"], cmd, want_text)
        if rerr:
            probs.append("the rendered %s shim for %s %s" % (w["agent"], cmd, rerr))
        try:  # RULE:I2-shim-rescan: the file the agent actually reads is scanned too, whatever it matches
            rerr = self._rendered_problems(m, w["agent"], cmd, _read_nofollow(p, MAX_FILE_BYTES, p))
        except EngineError as ex:
            rerr = "cannot be read (%s)" % ex.msg
        if rerr:
            probs.append("the wired %s shim %s %s" % (w["agent"], p, rerr))
        return probs

    def cmd_verify(self, eid):
        self.acquire(False)
        lock = self.read_lock()
        wiring = self.read_wiring()  # an invalid wiring file fails verify even with an empty lock (R11)
        if eid and eid not in lock:
            raise EngineError(EXIT_FAIL, "%s: not in the lock" % eid)
        ids = [eid] if eid else sorted(lock)
        results = []
        for i in ids:
            pr = self.verify_one(i, lock[i])
            results.append({"id": i, "ok": not pr, "problems": pr})
        wp = [self._wsig_problem] if self._wsig_problem else []
        for n, w in enumerate(wiring):  # R20: every entry, including those whose id is not in the lock
            if eid and w["id"] != eid:
                continue
            if w["id"] not in lock:
                wp.append("wiring entry %d (%s) belongs to %s, which is not in the lock" % (n, w["path"], w["id"]))
            if self._unbound(w):
                wp.append("wiring entry %d (%s) is not bound: not in this checkout's signed wiring record and the "
                          "file carries no managed-by marker; delete the entry (wire/unwire refuse until then)"
                          % (n, w["path"]))
        if wp:
            results.append({"id": "(wiring)", "ok": False, "problems": wp})
        ok = all(r["ok"] for r in results)
        if self.json:
            print(json.dumps({"ok": ok, "results": results}, sort_keys=True, indent=2))
        else:
            if not results:
                print("nothing to verify (lock is empty)")
            for r in results:
                print("%s %s" % ("OK  " if r["ok"] else "FAIL", r["id"]))
                for p in r["problems"]:
                    print("     " + disp(p))
        return EXIT_OK if ok else EXIT_VERIFY

    def cmd_lock(self):
        self.need_project()
        self.acquire(True)
        lock = self.read_lock()
        new = dict(lock)
        drift, changed, reconsent = [], [], []
        for eid, e in sorted(lock.items()):
            tree, origin = self.tree_of(eid)
            if origin == "bundled":
                rp = self.record_problems(eid, e)
                if rp:  # RULE:R17-lock-check
                    self.err("%s: not refreshed: %s" % (eid, rp[0]))
                    continue
                try:
                    m = self.load_manifest(tree)
                    caps = capabilities_of(m, tree)
                    cerr = content_problems(tree, m)
                except EngineError:
                    drift.append(eid)
                    continue
                if e.get("enabled") and (cerr or (e.get("consent") or {}).get("capabilities") != caps):  # RULE:R5-lock-reconsent
                    reconsent.append((eid, cerr))
                    continue
                e = dict(e)
                e["sha256"] = tree_digest(tree)
                e["version"] = m["extension"]["version"]
                if e != lock[eid]:
                    new[eid] = e
                    changed.append(eid)
            elif tree is None or tree_digest(tree) != e.get("sha256"):  # RULE:R7-lock-no-launder
                drift.append(eid)
        if self.dry:
            self.say("dry-run: would write %s" % self.p("extensions.lock.yml"))
            return EXIT_OK
        if self.commit(new, changed, stage="lock:written", force=True):
            self.audit("lock", "-")
        for d in drift:
            self.err("%s: installed tree differs from the lock; not refreshed (verify, then remove and add again)" % d)
        if not reconsent:
            self.say("lock written: %s" % self.p("extensions.lock.yml"))
        else:  # RULE:M3-partial-lock-message
            self.say("lock PARTIALLY written: %s (%d entr%s refreshed; NOT refreshed, consent needed: %s)"
                     % (self.p("extensions.lock.yml"), len(changed), "y" if len(changed) == 1 else "ies",
                        ", ".join(i for i, _c in reconsent)))
            for eid, cerr in reconsent:
                self.err("%s: not refreshed: %s; review it and grant it again with: enable %s"
                         % (eid, "; ".join(cerr) if cerr else "its capabilities or the content they bind changed "
                            "since consent", eid))
            raise EngineError(EXIT_REFUSED, "lock refuses to record new content without a new consent for: %s "
                                            "(run enable %s)" % (", ".join(i for i, _c in reconsent),
                                                                 " / enable ".join(i for i, _c in reconsent)))
        return EXIT_OK

    def cmd_catalog(self, path):
        try:
            cat = json_loads(_read_nofollow(path, 2 * 1024 * 1024, "catalog"))
            errs = _validate_catalog(cat)
        except (OSError, ValueError, EngineError) as ex:
            errs = ["catalog unreadable: %s" % (getattr(ex, "msg", None) or str(ex))[:200]]
        if errs:
            for e in errs:
                self.err(e)
            return EXIT_FAIL
        n_ext, n_rev = len(cat.get("extensions") or {}), len(cat.get("revoked") or [])
        if self.dry or not self.project:
            self.say("catalog %s valid: %d extensions, %d revoked (not imported%s)"
                     % (cat["catalog"]["id"], n_ext, n_rev, ": dry-run" if self.dry else ": no project"))
            return EXIT_OK
        self.acquire(True)
        try:
            old = self.read_catalog()
        except EngineError as ex:  # RULE:R9-old-catalog-unreadable
            if not self.o.get("replace"):
                raise EngineError(EXIT_VERIFY, "the previous catalog cannot be read, so its revocations cannot be "
                                               "kept (%s); inspect it, then pass --replace to import anyway" % ex.msg)
            self.err("WARNING: --replace: the unreadable previous catalog and its revocations are dropped (%s)" % ex.msg)
            old = None
        prev = [r for r in (old or {}).get("revoked") or [] if r not in (cat.get("revoked") or [])]
        if prev and not self.o.get("replace"):  # RULE:R9-keep-revocations
            cat = dict(cat)
            cat["revoked"] = list(cat.get("revoked") or []) + prev
            n_rev = len(cat["revoked"])
            self.err("kept %d previous revocation(s) (pass --replace to drop them)" % len(prev))
        elif prev:
            self.err("WARNING: --replace dropped %d previous revocation(s)" % len(prev))
        self.write_atomic(self.p("extensions.catalog.json"), json.dumps(cat, sort_keys=True, indent=2) + "\n")
        self.audit("catalog", "-", cat["catalog"]["id"])
        if self.json:
            print(json.dumps({"ok": True, "catalog": cat["catalog"], "extensions": n_ext, "revoked": n_rev}, sort_keys=True))
        else:
            print("imported catalog %s: %d extensions, %d revoked, install_allowed=%s"
                  % (cat["catalog"]["id"], n_ext, n_rev, str(cat["catalog"]["install_allowed"]).lower()))
        return EXIT_OK

    # ── wiring ──
    def _render(self, agent, eid, name, skill_path, desc_default):
        try:
            text = _read_nofollow(skill_path, MAX_FILE_BYTES, skill_path)
        except EngineError as ex:
            raise EngineError(EXIT_REFUSED, "cannot render %s: %s" % (skill_path, ex.msg))
        return self._render_text(agent, eid, name, text, desc_default, skill_path)

    def _render_text(self, agent, eid, name, text, desc_default, label):
        """The shim text for AGENT, rendered from the command text TEXT (read once by the caller)."""
        try:
            fm, body = front_matter(text)
        except ValueError as ex:
            raise EngineError(EXIT_REFUSED, "%s: %s" % (label, ex))
        fm = fm or {}
        body = body.strip("\n") + "\n"
        desc = fm.get("description") if isinstance(fm.get("description"), str) else desc_default
        desc = " ".join(desc.split())
        mark = "%s id=%s command=%s" % (MARKER, eid, name)
        if agent in ("opencode", "pi"):
            return "---\n# %s\ndescription: %s\n---\n\n%s" % (mark, json.dumps(desc, ensure_ascii=False), body)
        if agent in ("gemini", "qwen"):
            prompt = body.replace("$ARGUMENTS", "{{args}}")
            return "# %s\ndescription = %s\nprompt = %s\n" % (mark, _toml_str(desc), _toml_str(prompt))
        raise EngineError(EXIT_USAGE, "unknown agent %s" % agent)

    def _ensure_snapshot(self, w):
        """Publish the consented snapshot for wiring entry W (I2), or prove an existing one still matches. The
        snapshot is the staged copy (taken once from the locked tree, checked as a copy), moved into place by one
        rename; its digest is re-derived from the files themselves."""
        snap = self._snap(w["id"], w["command"], w["sha256"])
        if os.path.lexists(snap):
            if os.path.islink(snap) or not os.path.isdir(snap) or command_digest(snap) != w["sha256"]:  # RULE:I2-snap-intact
                raise EngineError(EXIT_VERIFY, "snapshot %s was changed after it was made; run unwire %s, then wire again"
                                  % (snap, w["id"]))
            return
        parent = os.path.dirname(snap)
        if not _inside(os.path.realpath(self._deep_existing(parent)), os.path.realpath(self.state)):  # RULE:R18-snapshots-dir
            raise EngineError(EXIT_REFUSED, "%s resolves outside the state directory" % parent)
        os.makedirs(parent, exist_ok=True)
        if not _inside(os.path.realpath(parent), os.path.realpath(self.state)):
            raise EngineError(EXIT_REFUSED, "%s resolves outside the state directory" % parent)
        staged = w["_src"]
        if command_digest(staged) != w["sha256"]:  # RULE:I2-snap-matches-checked
            raise EngineError(EXIT_VERIFY, "the staged copy of %s does not match its digest; run wire again" % w["command"])
        kill_point("wire:snapshot")
        os.rename(staged, snap)

    def _gc_snapshots(self, entries):
        """Remove every snapshot no wiring entry names (I2). Only <state>/extensions.snapshots/<id>/<cmd>/<64 hex>
        directories are considered; anything else there is left alone."""
        top = os.path.join(self.state, SNAP_DIR)
        if not os.path.isdir(top) or os.path.islink(top):
            return
        used = {(w["id"], w["command"], w["sha256"]) for w in entries if w.get("agent") == "claude" and w.get("sha256")}
        for eid in sorted(os.listdir(top)):
            ed = os.path.join(top, eid)
            if not ID_RE.match(eid) or os.path.islink(ed) or not os.path.isdir(ed):
                continue
            for cmd in sorted(os.listdir(ed)):
                cd = os.path.join(ed, cmd)
                if not NAME_RE.match(cmd) or os.path.islink(cd) or not os.path.isdir(cd):
                    continue
                for dig in sorted(os.listdir(cd)):
                    sd = os.path.join(cd, dig)
                    if SHA256_RE.match(dig) and (eid, cmd, dig) not in used and not os.path.islink(sd) \
                            and os.path.isdir(sd):  # RULE:I2-snap-gc
                        self.rm_tree(sd, top)
                if not os.listdir(cd):
                    os.rmdir(cd)
            if not os.listdir(ed):
                os.rmdir(ed)

    @staticmethod
    def _rendered_problems(m, agent, name, content):
        """M2: the text an agent actually reads is the RENDERED shim ($ARGUMENTS becomes {{args}} for Gemini and
        Qwen, so '!$ARGUMENTS' becomes the shell injection '!{{args}}'). It is scanned again; a construct class the
        command does not declare is refused. Returns a reason or None."""
        caps = m.get("capabilities") or {}
        decl = {"shell": name in (caps.get("agent_shell") or []), "files": name in (caps.get("reads_files") or [])}
        try:
            found = agent_constructs(content)
        except ValueError as ex:
            return "cannot be analysed (%s)" % ex
        extra = sorted(cls for cls in found if not decl[cls])
        if extra:
            return ("contains %s that capabilities.%s does not declare (the source text becomes a construct only after "
                    "rendering)" % (", ".join("agent " + x for x in extra),
                                    " / ".join("agent_shell" if x == "shell" else "reads_files" for x in extra)))
        return None

    def _deep_existing(self, path):
        while not os.path.lexists(path):
            path = os.path.dirname(path)
        return path

    def _stage_root(self):
        """The private staging directory of this wire run: <state>/extensions.snapshots/.stage-<pid>-<hex>, mode
        0700, on the same filesystem as the snapshots (so a staged command directory is published by one atomic
        rename). The snapshots directory itself is checked first (R18); dead stages are swept by recover (I2)."""
        if self._wstage is None:
            top = self.p(SNAP_DIR)
            if os.path.lexists(top) and not stat.S_ISDIR(os.lstat(top).st_mode):  # RULE:R18-snapshots-dir
                raise EngineError(EXIT_REFUSED, "%s is not a real directory; refusing to use it" % top)
            if not _inside(os.path.realpath(self._deep_existing(top)), os.path.realpath(self.state)):
                raise EngineError(EXIT_REFUSED, "%s resolves outside the state directory" % top)
            os.makedirs(top, mode=0o755, exist_ok=True)
            self._wstage = os.path.join(top, ".stage-%d-%s" % (os.getpid(), os.urandom(4).hex()))
            os.mkdir(self._wstage, 0o700)
        return self._wstage

    def _drop_stage(self):
        st, self._wstage = self._wstage, None
        if st and os.path.lexists(st):
            self.rm_tree(st, self.p(SNAP_DIR))

    def cmd_wire(self, eid, agents, target):
        self._wstage, self._wn = None, 0
        try:
            return self._cmd_wire(eid, agents, target)
        finally:
            self._drop_stage()

    def _cmd_wire(self, eid, agents, target):
        self.need_project()
        target = os.path.normpath(os.path.abspath(target or self.project))
        if not os.path.isdir(target):
            raise EngineError(EXIT_REFUSED, "--target %s: not a directory" % target)
        proj = os.path.realpath(self.project)
        if not _inside(os.path.realpath(target), proj):  # RULE:R11-target-inside
            raise EngineError(EXIT_REFUSED, "--target %s resolves outside the project %s" % (target, self.project))
        root_rel = os.path.relpath(os.path.realpath(target), proj)
        self.acquire(True)
        lock = self.read_lock()
        if eid:
            if not (lock.get(eid) or {}).get("enabled"):
                raise EngineError(EXIT_REFUSED, "%s is not enabled; run enable %s first" % (eid, eid))
            ids = [eid]
        else:
            ids = [i for i in sorted(lock) if lock[i].get("enabled")]
        for i in ids:
            rp = self.record_problems(i, lock[i])
            if rp:  # RULE:R17-wire-check
                raise EngineError(EXIT_VERIFY, "%s: refusing to wire a lock entry that fails its state check:\n  %s"
                                  % (i, "\n  ".join(rp)))
        wiring = self.read_wiring()
        self._require_bound(wiring)  # R20
        by_path = {w["path"]: w for w in wiring}
        plan = []
        seen = {}
        for i in ids:
            tree, m, e = self._entry_for(i, lock)
            race_point("wire:before-copy")
            # I2: the locked tree is read ONCE, into a private staged copy; its digest is computed from the bytes
            # that were read and must equal the lock's; every check below, every shim text and every snapshot is
            # taken from that copy, so nothing that happens to the live tree afterwards reaches the agent
            stage = os.path.join(self._stage_root(), "x%d" % self._wn)
            self._wn += 1
            hashes = _copy_tree(tree, stage, False)
            race_point("wire:after-copy")
            if digest_of_hashes(hashes) != e.get("sha256"):  # RULE:I2-copy-matches-lock
                raise EngineError(EXIT_VERIFY, "%s: the extension tree changed while it was being wired (it no longer "
                                               "matches the lock); run verify, then wire again" % i)
            m = self.load_manifest(stage)
            why = self.revoked(i, m["extension"]["version"], e.get("sha256"))
            if why:  # RULE:R9-wire-revocation
                raise EngineError(EXIT_REFUSED, "%s %s is revoked by the catalog: %s; not wiring it (disable it)"
                                  % (i, m["extension"]["version"], disp(why)))
            if (e.get("consent") or {}).get("capabilities") != capabilities_of(m, stage):  # RULE:R5-wire-consent
                raise EngineError(EXIT_VERIFY, "%s: capabilities changed since consent; run enable %s again to review "
                                               "and grant them before wiring" % (i, i))
            cerr = content_problems(stage, m)
            if cerr:  # RULE:R21-wire
                raise EngineError(EXIT_REFUSED, "%s: refusing to wire undeclared agent-side constructs:\n  %s"
                                  % (i, "\n  ".join(cerr)))
            for c in (m.get("provides") or {}).get("commands") or []:
                if c["name"] in seen and seen[c["name"]] != i:
                    raise EngineError(EXIT_REFUSED, "command %s provided by both %s and %s" % (c["name"], seen[c["name"]], i))
                seen[c["name"]] = i
                cdir = os.path.join(stage, "commands", c["name"])
                for a in agents:
                    rel = self._shim_rel(a, root_rel, c["name"])
                    path = self._wabs(rel)
                    if not _inside(os.path.realpath(self._deep_existing(os.path.dirname(path))), proj):
                        raise EngineError(EXIT_REFUSED, "%s: a parent directory resolves outside the project" % path)
                    if a == "claude":
                        dig = command_digest_of(hashes, "commands/%s/" % c["name"])
                        link = self._link_texts(i, c["name"], rel, dig)[0]
                        plan.append({"id": i, "command": c["name"], "agent": a, "path": rel, "kind": "symlink",
                                     "target": link, "sha256": dig, "root": root_rel, "_src": cdir})
                    else:
                        content = self._render_text(a, i, c["name"], _read_nofollow(
                            os.path.join(cdir, "SKILL.md"), MAX_FILE_BYTES, "commands/%s/SKILL.md" % c["name"]),
                            c["description"], "commands/%s/SKILL.md" % c["name"])
                        rerr = self._rendered_problems(m, a, c["name"], content)
                        if rerr:  # RULE:M2-rendered-rescan
                            raise EngineError(EXIT_REFUSED, "%s: the rendered %s shim for %s %s" % (i, a, c["name"], rerr))
                        plan.append({"id": i, "command": c["name"], "agent": a, "path": rel, "kind": "file",
                                     "target": None, "sha256": hashlib.sha256(content.encode()).hexdigest(),
                                     "root": root_rel, "_content": content})
        for w in plan:  # conflict check before any write
            p = self._wabs(w["path"])
            if not os.path.lexists(p):
                continue
            rec = by_path.get(w["path"])
            same = rec is not None and rec.get("id") == w["id"]
            if w["kind"] == "symlink":
                if os.path.islink(p) and (os.readlink(p) == w["target"] or (same and os.readlink(p) == rec.get("target"))):
                    continue
            elif _is_reg(p):
                h = _sha_file(p)
                if h == w["sha256"] or (same and h == rec.get("sha256")):  # RULE:R11-no-overwrite-edited
                    continue
                if same:
                    raise EngineError(EXIT_REFUSED, "%s was edited after wiring; refusing to overwrite it "
                                                    "(move your edits away, then unwire and wire again)" % p)
            raise EngineError(EXIT_REFUSED, "%s exists and is not managed by this extension; refusing to overwrite" % p)
        if self.dry:
            for w in plan:
                self.say("dry-run: would wire %s -> %s" % (w["command"], w["path"]))
            return EXIT_OK
        changed = False
        made = []
        # m4: a journal names every shim this run may create a temporary file next to, so recovery can
        # remove a temporary link or file left by a crash between creating and renaming it
        self.write_atomic(self.p("extensions.txn"), json.dumps(
            {"op": "wire", "pid": os.getpid(), "entries": [{k: v for k, v in w.items() if not k.startswith("_")}
                                                           for w in plan]}))
        for n, w in enumerate(plan):
            p = self._wabs(w["path"])
            os.makedirs(os.path.dirname(p), exist_ok=True)
            if not _inside(os.path.realpath(os.path.dirname(p)), proj):
                raise EngineError(EXIT_REFUSED, "%s: directory resolves outside the project" % p)
            if w["kind"] == "symlink":
                self._ensure_snapshot(w)
                if not (os.path.islink(p) and os.readlink(p) == w["target"]):
                    tmp = "%s.tmp-%d-%s" % (p, os.getpid(), os.urandom(4).hex())
                    os.symlink(w["target"], tmp)
                    kill_point("wire:tmp")
                    os.replace(tmp, p)
                    changed = True
            else:
                if not (_is_reg(p) and _sha_file(p) == w["sha256"]):
                    self.write_atomic(p, w["_content"])
                    changed = True
            if n == 0:
                kill_point("wire:partial")
            rec = {k: v for k, v in w.items() if not k.startswith("_")}
            by_path[w["path"]] = rec
            made.append(rec)
        if self.write_wiring(list(by_path.values()), trusted=made) or changed:
            self.audit("wire", eid or "*", ",".join(agents))
        self._gc_snapshots(list(by_path.values()))
        os.unlink(self.p("extensions.txn"))
        self.say("wired %d shim(s) for %d extension(s) into %s" % (len(plan), len(ids), target))
        return EXIT_OK

    def _unwire(self, eid, agents, target):
        wiring = self.read_wiring()  # validated: every path is a shim path inside the project (R11)
        self._require_bound(wiring)  # R20: an unbound entry anywhere refuses before any unlink
        keep, removed = [], 0
        tgt = None
        if target:
            tgt = os.path.relpath(os.path.realpath(os.path.normpath(os.path.abspath(target))),
                                  os.path.realpath(self.project))
        for w in wiring:
            match = (eid is None or w["id"] == eid) and w["agent"] in agents and (tgt is None or w["root"] == tgt)
            if not match:
                keep.append(w)
                continue
            p = self._wabs(w["path"])
            if w["kind"] == "symlink":
                if os.path.islink(p) and os.readlink(p) == w["target"]:
                    os.unlink(p)
                    removed += 1
            elif _is_reg(p):
                if _sha_file(p) == w["sha256"]:  # RULE:W2-unwire-sha
                    os.unlink(p)
                    removed += 1
                else:
                    self.err("%s was modified after wiring; left in place" % p)
        if len(keep) != len(wiring):
            self.write_wiring(keep)
        self._gc_snapshots(keep)
        return removed

    def cmd_unwire(self, eid, agents, target):
        self.need_project()
        self.acquire(True)
        if self.dry:
            n = sum(1 for w in self.read_wiring() if (eid is None or w["id"] == eid) and w["agent"] in agents)
            self.say("dry-run: would remove %d shim(s)" % n)
            return EXIT_OK
        n = self._unwire(eid, agents, target)
        if n:
            self.audit("unwire", eid or "*", ",".join(agents))
        self.say("removed %d shim(s)" % n)
        return EXIT_OK

    def cmd_doctor(self):
        self.acquire(False)
        checks = []

        def add(name, ok, detail=""):
            checks.append({"name": name, "ok": bool(ok), "detail": detail})
        add("python", sys.version_info >= (3, 8), sys.version.split()[0])
        add("git", shutil.which("git") is not None, shutil.which("git") or "not found")
        add("safe_rm", os.path.isfile(self.safe_rm), os.path.realpath(self.safe_rm))
        add("root", True, self.root)
        add("project", self.project is not None, self.project or "none (pass --project-root)")
        if os.path.isdir(self.inst_dir):
            g = _git(["-C", self.root, "rev-parse", "--git-path", "info/exclude"])
            if g.returncode == 0:
                ex = g.stdout.strip()
                ex = ex if os.path.isabs(ex) else os.path.join(self.root, ex)
                try:
                    has = any(l.strip().endswith("extensions/_installed/")
                              for l in _read_nofollow(ex, 1 << 20, ex).splitlines()) if os.path.lexists(ex) else False
                except EngineError:
                    has = False
                add("git-exclude", has, ex)
        lock = {}
        try:
            lock = self.read_lock()
            add("lock", True, "%d entries" % len(lock))
        except EngineError as ex:
            add("lock", False, ex.msg)
        if self.state:
            add("journal", not os.path.lexists(self.p("extensions.txn")) and not self._journal_bad,
                "invalid journal: %s" % self._journal_bad if self._journal_bad else "no interrupted transaction")
            try:
                self.read_wiring()
                add("wiring", True, "valid")
            except EngineError as ex:
                add("wiring", False, ex.msg)
        for eid in sorted(lock):
            try:
                pr = self.verify_one(eid, lock[eid])
            except EngineError as ex:
                pr = [ex.msg]
            add("verify:" + eid, not pr, "; ".join(pr))
        if self.project:
            bare = os.path.join(self.project, ".claude", "skills", "constitution")
            if os.path.lexists(bare):
                tgt = os.path.realpath(bare)
                add("bare-/constitution", tgt.startswith(os.path.realpath(self.root) + os.sep),
                    "%s -> %s" % (bare, tgt))
        ok = all(c["ok"] for c in checks)
        res = {"ok": ok, "root": self.root, "project_root": self.project,
               "layout": layout_of(self.root, self.project), "checks": checks,
               "constitution_version": constitution_version(self.root)}
        if self.json:
            print(json.dumps(res, sort_keys=True, indent=2))
        else:
            print("layout: %s  root: %s  project: %s" % (res["layout"], self.root, self.project))
            for c in checks:
                print("%s %-22s %s" % ("ok  " if c["ok"] else "FAIL", c["name"], c["detail"]))
        return EXIT_OK if ok else EXIT_FAIL


def _validate_catalog(c):
    errs = []
    if not isinstance(c, dict):
        return ["catalog: top level must be an object"]
    for k in c:
        if k not in ("schema_version", "catalog", "revoked", "extensions"):
            errs.append("catalog: unknown key %r" % k)
    if c.get("schema_version") != "1.0":
        errs.append("catalog.schema_version must be \"1.0\"")
    meta = c.get("catalog")
    if not isinstance(meta, dict) or not isinstance(meta.get("id"), str) or not isinstance(meta.get("install_allowed"), bool) \
            or meta.get("trust_tier") not in ("vetted", "community") or set(meta) - {"id", "install_allowed", "trust_tier", "name"}:
        errs.append("catalog.catalog must be {id, install_allowed: bool, trust_tier}")
    rv = c.get("revoked", [])
    if not isinstance(rv, list) or any(not isinstance(r, dict) or not ID_RE.match(str(r.get("id", ""))) or
                                       not (r.get("version") == "*" or is_semver(r.get("version"))) or set(r) - {"id", "version", "reason", "sha256"}
                                       or ("sha256" in r and not SHA256_RE.match(str(r["sha256"])))
                                       for r in rv):
        errs.append("catalog.revoked must be a list of {id, version (semver or \"*\"), reason[, sha256]}")
    ex = c.get("extensions", {})
    if not isinstance(ex, dict):
        errs.append("catalog.extensions must be an object")
    else:
        for eid, ent in ex.items():
            if not ID_RE.match(eid) or not isinstance(ent, dict) or set(ent) - {"description", "latest", "releases", "tags", "repository"}:
                errs.append("catalog.extensions.%s: invalid entry" % eid[:64])
                continue
            rels = ent.get("releases") if ent.get("releases") is not None else {}
            if not isinstance(rels, dict):
                errs.append("catalog.extensions.%s.releases must be an object" % eid)
                continue
            if "latest" in ent and (not is_semver(ent["latest"]) or ent["latest"] not in rels):  # RULE:M2-latest
                errs.append("catalog.extensions.%s.latest must be a release version listed in releases" % eid)
            if "description" in ent and not isinstance(ent["description"], str) or \
                    "repository" in ent and not isinstance(ent["repository"], str) or \
                    "tags" in ent and (not isinstance(ent["tags"], list) or
                                       any(not isinstance(t, str) or not TAG_RE.match(t) for t in ent["tags"])):
                errs.append("catalog.extensions.%s: description/repository must be strings, tags a list of tags" % eid)
            for ver, r in rels.items():
                if not is_semver(ver) or not isinstance(r, dict) or not isinstance(r.get("url"), str) \
                        or not SHA256_RE.match(str(r.get("sha256", ""))) \
                        or ("git_sha" in r and not SHA40_RE.match(str(r["git_sha"]))) \
                        or set(r) - {"url", "sha256", "git_sha"}:
                    errs.append("catalog.extensions.%s.releases.%s: needs url, sha256 (64-hex), optional git_sha (40-hex)" % (eid, ver[:32]))
                elif url_problem(r["url"]):
                    errs.append("catalog.extensions.%s.releases.%s.url: %s" % (eid, ver[:32], url_problem(r["url"])))
    return errs


def _toml_str(s):
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _is_reg(p):
    try:
        return stat.S_ISREG(os.lstat(p).st_mode)
    except OSError:
        return False


def _sha_file(p):
    h = hashlib.sha256()
    with os.fdopen(_open_regular(p, p), "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def command_digest(cdir):
    """sha256 over the sorted (relpath, file sha256) list of the regular files below CDIR. A symlink or any
    other non-regular entry is refused: a snapshot holds plain files only (I2)."""
    lines = []
    for dp, dns, fns in os.walk(cdir, onerror=_walk_error):
        dns.sort()
        for n in sorted(dns + fns):
            full = os.path.join(dp, n)
            st = os.lstat(full)
            rel = os.path.relpath(full, cdir)
            if stat.S_ISDIR(st.st_mode):
                continue
            if not stat.S_ISREG(st.st_mode):
                raise EngineError(EXIT_REFUSED, "%s: not a regular file (a command directory holds plain files only)"
                                  % disp(rel))
            lines.append("%s\0%s\n" % (rel, _sha_file(full)))
    return hashlib.sha256("".join(sorted(lines)).encode("utf-8", "surrogateescape")).hexdigest()


def _ident_of(path):
    """[device, inode, mtime_ns] of the directory at PATH (lstat). A rename keeps all three, so the staged
    directory and the installed tree it becomes carry the same identity; a different tree never does."""
    try:
        st = os.lstat(path)
    except OSError:
        return None
    return [st.st_dev, st.st_ino, st.st_mtime_ns]


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _copy_tree(src, dst, skip_git):
    """Copy regular files and directories only, normalising modes (0644/0755). Never executes. This is the only read of
    SRC whose bytes are trusted: the caller may hash SRC beforehand (file_hashes, to validate the source), but
    that earlier read is only compared with, never installed from. It returns {relpath: sha256} of the bytes it
    read and wrote, so a digest taken from the return value (or from DST) describes exactly what was copied,
    whatever SRC does afterwards."""
    hashes = {}
    n_files = n_dirs = n_bytes = 0
    os.makedirs(dst, mode=0o755)
    for dp, dns, fns in os.walk(src, onerror=_walk_error):
        rel = os.path.relpath(dp, src)
        if skip_git and rel == ".":
            dns[:] = [d for d in dns if d != ".git"]
        if any(x.lower() == ".git" for x in dns + fns):
            raise EngineError(EXIT_REFUSED, "%s: embedded git metadata (.git) is not allowed" % rel)
        dns.sort()
        if rel != "." and rel.count(os.sep) + 1 > MAX_TREE_DEPTH:  # RULE:R2-copy-bounds
            raise EngineError(EXIT_REFUSED, "%s: directories nested deeper than %d levels" % (rel, MAX_TREE_DEPTH))
        n_dirs += len(dns)
        if n_dirs > MAX_DIRS:
            raise EngineError(EXIT_REFUSED, "more than %d directories" % MAX_DIRS)
        for d in dns:
            if stat.S_ISLNK(os.lstat(os.path.join(dp, d)).st_mode):  # RULE:R2-copy-symlink-dir
                raise EngineError(EXIT_REFUSED, "%s: a symlink (symlinks are not allowed in an extension tree)"
                                  % os.path.join(rel, d))
            os.makedirs(os.path.join(dst, rel, d), mode=0o755, exist_ok=True)
        for n in sorted(fns):
            if rel == "." and n == CHECKSUMS:
                continue
            sp = os.path.join(dp, n)
            st = os.lstat(sp)
            if not stat.S_ISREG(st.st_mode) or st.st_nlink > 1:
                raise EngineError(EXIT_REFUSED, "%s: not a single-link regular file" % os.path.join(rel, n))
            n_files += 1
            n_bytes += st.st_size
            if n_files > MAX_FILES or n_bytes > MAX_TREE_BYTES or st.st_size > MAX_FILE_BYTES:
                raise EngineError(EXIT_REFUSED, "%s: tree exceeds the limits (%d files, %d bytes, %d bytes per file)"
                                  % (os.path.join(rel, n), MAX_FILES, MAX_TREE_BYTES, MAX_FILE_BYTES))
            dp2 = os.path.join(dst, rel, n)
            race_point("copy-before-open")
            fd = _open_regular(sp, os.path.join(rel, n))
            # RULE:S2-fstat: the checks above read the path BEFORE it was opened; what is copied is the opened
            # descriptor, so the same checks are made on it: the very file lstat described, a regular file, one link
            fst = os.fstat(fd)
            if not stat.S_ISREG(fst.st_mode) or fst.st_nlink > 1 \
                    or (fst.st_dev, fst.st_ino) != (st.st_dev, st.st_ino):
                os.close(fd)
                raise EngineError(EXIT_REFUSED, "%s: changed while it was copied (not the single-link regular file "
                                  "that was checked)" % os.path.join(rel, n))
            fo_fd = os.open(dp2, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            h = hashlib.sha256()
            with os.fdopen(fd, "rb") as fi, os.fdopen(fo_fd, "wb") as fo:
                got = 0
                for chunk in iter(lambda: fi.read(65536), b""):
                    race_point("copy-chunk")
                    got += len(chunk)
                    # RULE:R2-copy-read-cap: the caps above use the size seen before the copy; a file that grows
                    # while it is read is stopped at the per-file and the tree cap, never read to EOF
                    if got > MAX_FILE_BYTES or n_bytes - st.st_size + got > MAX_TREE_BYTES:
                        raise EngineError(EXIT_REFUSED, "%s: grew while it was copied; the tree exceeds the limits "
                                          "(%d bytes, %d bytes per file)" % (os.path.join(rel, n), MAX_TREE_BYTES,
                                                                              MAX_FILE_BYTES))
                    h.update(chunk)
                    fo.write(chunk)
            os.chmod(dp2, 0o755 if st.st_mode & 0o111 else 0o644)
            hashes[n if rel == "." else rel + "/" + n] = h.hexdigest()
    return hashes


# ── CLI ────────────────────────────────────────────────────────────────────────────────────
VALUE_FLAGS = {"--root": "root", "--project-root": "project_root", "--sha": "sha", "--sha256": "sha256",
               "--waiver-id": "waiver_id", "--agent": "agent", "--target": "target"}
BOOL_FLAGS = {"--json": "json", "--dry-run": "dry_run", "--yes": "yes", "--dev": "dev", "--replace": "replace",
              "--help": "help", "-h": "help"}
GLOBAL = {"root", "project_root", "json", "dry_run", "help"}
CMDS = {
    "validate": (1, 1, set()), "list": (0, 0, set()), "info": (1, 1, set()),
    "add": (1, 1, {"sha", "sha256", "dev", "yes", "waiver_id"}), "remove": (1, 1, {"yes"}),
    "enable": (1, 1, {"yes"}), "disable": (1, 1, set()), "verify": (0, 1, set()), "lock": (0, 0, set()),
    "doctor": (0, 0, set()), "catalog": (1, 1, {"replace"}), "wire": (0, 1, {"agent", "target"}),
    "unwire": (0, 1, {"agent", "target"}),
}
ID_ARG_CMDS = {"info", "remove", "enable", "disable", "verify", "wire", "unwire"}


def parse_args(argv):
    opts = {k: False for k in BOOL_FLAGS.values()}
    pos = []
    i = 0
    dash = False
    while i < len(argv):
        a = argv[i]
        if dash:
            pos.append(a)
        elif a == "--":
            dash = True
        elif a in BOOL_FLAGS:
            opts[BOOL_FLAGS[a]] = True
        elif a.split("=", 1)[0] in VALUE_FLAGS:
            k = VALUE_FLAGS[a.split("=", 1)[0]]
            if "=" in a:
                v = a.split("=", 1)[1]
            else:
                i += 1
                if i >= len(argv):
                    raise EngineError(EXIT_USAGE, "%s needs a value" % a)
                v = argv[i]
            opts[k] = v
        elif a.startswith("-"):
            raise EngineError(EXIT_USAGE, "unknown option %s" % a.split("=", 1)[0][:40])
        else:
            pos.append(a)
        i += 1
    return opts, pos


def term_safe(s):
    """S with every control, format (bidi), separator, surrogate or private-use character escaped, except
    newline and tab: the one sink every byte the engine prints passes through (M1)."""
    return "".join(c if c in "\n\t" or unicodedata.category(c) not in _BAD_CATS else "\\u%04x" % ord(c)
                   for c in str(s))


class _TermSafeStream(object):
    def __init__(self, raw):
        self._raw = raw

    def write(self, s):
        return self._raw.write(term_safe(s))  # RULE:M1-sink

    def __getattr__(self, name):
        return getattr(self._raw, name)


def main(argv, usage_text):
    """Run one command with stdout and stderr passed through term_safe (M1)."""
    saved = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = _TermSafeStream(saved[0]), _TermSafeStream(saved[1])
    try:
        return _main(argv, usage_text)
    finally:
        sys.stdout, sys.stderr = saved


def _main(argv, usage_text):
    try:
        opts, pos = parse_args(argv)
        if opts["help"]:
            print(usage_text)
            return EXIT_OK
        if not pos:
            raise EngineError(EXIT_USAGE, "missing command (see --help)")
        cmd, args = pos[0], pos[1:]
        if cmd not in CMDS:
            raise EngineError(EXIT_USAGE, "unknown command %s" % cmd[:40])
        lo, hi, allowed = CMDS[cmd]
        if not lo <= len(args) <= hi:
            raise EngineError(EXIT_USAGE, "%s: wrong number of arguments" % cmd)
        for k, v in opts.items():
            if k not in GLOBAL and v not in (False, None) and k not in allowed:
                raise EngineError(EXIT_USAGE, "%s does not accept --%s" % (cmd, k.replace("_", "-")))
        if cmd in ID_ARG_CMDS and args and not ID_RE.match(args[0]):
            raise EngineError(EXIT_USAGE, "invalid extension id (must match ^[a-z0-9][a-z0-9-]*$)")
        if opts.get("sha") and not SHA40_RE.match(opts["sha"]):
            raise EngineError(EXIT_USAGE, "--sha must be a full 40-hex commit id")
        if opts.get("sha256") and not SHA256_RE.match(opts["sha256"]):
            raise EngineError(EXIT_USAGE, "--sha256 must be 64 lowercase hex characters")
        if opts.get("waiver_id") and not WAIVER_RE.match(opts["waiver_id"]):
            raise EngineError(EXIT_USAGE, "--waiver-id must match [A-Za-z0-9][A-Za-z0-9._-]*")
        if opts.get("waiver_id") and secret_shaped_id(opts["waiver_id"]):  # RULE:R16-waiver-secret
            raise EngineError(EXIT_USAGE, "--waiver-id looks like a credential or token (value withheld); it is "
                                          "recorded in the tracked lock and audit log, so use a ticket-style id")
        agents = None
        if cmd in ("wire", "unwire"):
            ag = opts.get("agent")
            if not ag:
                raise EngineError(EXIT_USAGE, "%s needs --agent (%s|all)" % (cmd, "|".join(WIRE_AGENTS)))
            if ag == "all":
                agents = WIRE_AGENTS
            elif ag in WIRE_AGENTS:
                agents = (ag,)
            else:
                raise EngineError(EXIT_USAGE, "--agent must be one of %s, all" % ", ".join(WIRE_AGENTS))
        if cmd == "validate":
            eng = Engine.__new__(Engine)
            eng.o, eng.json, eng.dry, eng._manifest_cache = opts, opts["json"], opts["dry_run"], {}
            return eng.cmd_validate(args[0])
        eng = Engine(opts)
        if opts["dry_run"] and not opts["json"]:
            print("dry-run: no changes will be written")
        a0 = args[0] if args else None
        if cmd == "list":
            return eng.cmd_list()
        if cmd == "info":
            return eng.cmd_info(a0)
        if cmd == "add":
            return eng.cmd_add(a0)
        if cmd == "remove":
            return eng.cmd_remove(a0)
        if cmd == "enable":
            return eng.cmd_enable(a0)
        if cmd == "disable":
            return eng.cmd_disable(a0)
        if cmd == "verify":
            return eng.cmd_verify(a0)
        if cmd == "lock":
            return eng.cmd_lock()
        if cmd == "doctor":
            return eng.cmd_doctor()
        if cmd == "catalog":
            return eng.cmd_catalog(a0)
        if cmd == "wire":
            return eng.cmd_wire(a0, agents, opts.get("target"))
        if cmd == "unwire":
            return eng.cmd_unwire(a0, agents, opts.get("target"))
    except EngineError as ex:
        if ex.code == EXIT_OK:
            print(ex.msg)
            return EXIT_OK
        print("constitution_ext: " + ex.msg, file=sys.stderr)
        if ex.code == EXIT_USAGE:
            print("usage: constitution_ext.sh [--root DIR] [--project-root DIR] [--json] [--dry-run] <command> ... (--help)",
                  file=sys.stderr)
        if "--json" in argv:
            print(json.dumps({"ok": False, "error": ex.msg, "exit": ex.code}, sort_keys=True))
        return ex.code
    except KeyboardInterrupt:
        return 130
    except (ValueError, OSError, UnicodeError, ext_yaml.YamlError) as ex:  # never a traceback (MINOR)
        print("constitution_ext: error: %s" % disp(str(ex))[:300], file=sys.stderr)
        if "--json" in argv:
            print(json.dumps({"ok": False, "error": disp(str(ex))[:300], "exit": EXIT_FAIL}, sort_keys=True))
        return EXIT_FAIL
    except Exception as ex:  # noqa: BLE001
        print("constitution_ext: internal error (%s): %s" % (type(ex).__name__, disp(str(ex))[:300]), file=sys.stderr)
        return EXIT_FAIL
    return EXIT_FAIL


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ.get("CONSTITUTION_EXT_USAGE", "see constitution_ext.sh --help")))
