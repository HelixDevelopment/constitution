#!/usr/bin/env python3
"""decisions_engine.py - the decisions wizard engine (called by constitution_decisions.sh).

Records decision-model choices (Jev decision layer, llmctl, hosted endpoints, per-agent wiring)
as LOCAL PROJECT OVERRIDES that inherit from the constitution (§11.4.35). A locked rule can only
be kept or tightened, never weakened. Plan: docs/design/decisions_wizard_plan.md.

Safety: no network, no LLM, no subprocess except the read-only jev-status.sh --no-validate and
(with --probe) `llmctl plan --json`; writes only inside the project (plus the user file with
--scope user); never edits settings.json; never writes into .git/ or (except its own files)
.constitution/; values and keys that look like credentials are refused and never echoed; every
write happens under an flock (O_NOFOLLOW), after a re-read of the current state, with a backup
first, atomic replace, an intent journal, and a re-parse of the dumped file before it is written.

The decisions.sha256 sidecar is PROVENANCE ONLY: it tells a wizard write from a hand edit. It is
not a security control (anyone who can edit the file can edit the sidecar).

Cross-layer contradictions (user vs project layer, round-4 I-1) are REPORTED by every read and recovery path and
never refuse it; only a write that would create a NEW contradiction is refused. Write targets inside a git
submodule, another repository or the inherited constitution are refused (exit 3); a project root must hold or name
an inherited constitution (--inherits) and is never the HOME directory unless --inherits is given explicitly.

Exit codes: 0 ok, 1 internal, 2 usage/no TTY, 3 precondition, 4 refused, 5 lock busy.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pwd
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata

VERSION = "1.4.0"
ENGINE_DIR = os.path.dirname(os.path.abspath(__file__))
CONST_ROOT = os.path.abspath(os.path.join(ENGINE_DIR, "..", ".."))
BEGIN = "<!-- BEGIN constitution-decisions"
END = "<!-- END constitution-decisions"
# Structure-aware markers (review I-3): a marker is a WHOLE line, outside fenced code, with the exact token
# (so `constitution-decisions-legacy` and `<!-- END ... --> trailing text` are NOT our markers).
BEGIN_RE = re.compile(r"<!-- BEGIN constitution-decisions(?: \([^\r\n]*\))? -->")
END_RE = re.compile(r"<!-- END constitution-decisions -->")
# CommonMark fenced code (spec 0.31 §4.5), top level: up to 3 spaces of indentation (a tab is >= 4 columns, so a
# leading tab is never a fence), then >= 3 backticks or >= 3 tildes. A BACKTICK fence's info string may not contain a
# backtick (such a line is not a fence at all). A fence closes only with the same character, at least as long, up to 3
# spaces of indentation and nothing but spaces/tabs after it; an unclosed fence runs to the end of the document.
FENCE_OPEN_RE = re.compile(r"( {0,3})(`{3,}|~{3,})(.*)")
FENCE_CLOSE_RE = re.compile(r" {0,3}(`{3,}|~{3,})[ \t]*")
DEFAULT_DOCS = ("CLAUDE.md", "AGENTS.md", "GEMINI.md", "QWEN.md")
AGENTS = ("claude", "kimi", "pi", "opencode")
# §11.4.279(E)(3): review, merge, finding-layer, QA, readiness, evidence and verifier decisions are never
# served. Matched as a CLASS (substring stems), so code_review, pre_merge, qa_check, verify_step are covered.
EXCLUDED_STEMS = ("review", "merge", "conflict", "finding", "qa", "readiness", "ready", "evidence",
                  "verif", "verdict")
# Default-deny for enforce: only these question types may be set to enforce locally (data; extend by review).
# "gate" is the only type observed in claude_toolkit today; the others are the routing/truncation judgments the
# decision layer is documented for (UNCONFIRMED as live question names).
ENFORCE_ELIGIBLE = ("gate", "route", "routing", "truncate", "truncation", "tier")
KEY_VARS_FALLBACK = ("TYPESAFE_API_KEY", "OPENROUTER_API_KEY", "LLMCTL_API_KEY")
ENDPOINT_ORDER = ("local", "lan", "hosted")
FORBIDDEN_TOP = (".git", ".constitution", ".constitution-install-backup")
TYPE_RE = re.compile(r"[a-z][a-z0-9_]{0,39}")
PROFILE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
KEY_SHAPE_RE = re.compile(r"[a-z][a-z0-9_]{0,39}(?:\.[a-z][a-z0-9_]{0,39}){1,3}")
INHERITS_RE = re.compile(r"\.|(?:[A-Za-z0-9_][A-Za-z0-9._-]*)(?:/[A-Za-z0-9_][A-Za-z0-9._-]*)*")
SECRET_RES = (re.compile(r"(sk|pk|rk)-[A-Za-z0-9_-]{12,}"), re.compile(r"gh[pousr]_[A-Za-z0-9]{12,}"),
              re.compile(r"AKIA[A-Z0-9]{12,}"), re.compile(r"xox[abprs]-"),
              # generic token: a 32+ run of the token alphabet holding at least one digit AND one letter. Words joined
              # by '/' or '-' (anchor text such as review/merge/finding/QA/...) carry no digit and are left alone.
              re.compile(r"(?=[A-Za-z0-9+/_=-]*[0-9])(?=[A-Za-z0-9+/_=-]*[A-Za-z])[A-Za-z0-9+/_=-]{32,}"))


class Refused(Exception):
    """Validation refusal (exit 4)."""


class Precondition(Exception):
    """Precondition failure (exit 3)."""


class Usage(Exception):
    """Usage error (exit 2)."""


class Foreign(Precondition):
    """A write target that belongs to another repository or to the inherited constitution (exit 3)."""


def pinned_key_vars():
    """Key variable NAMES from the claude_toolkit pin (§11.4.279(E)(1)); fallback to the documented three."""
    pin = os.path.join(CONST_ROOT, "submodules", "claude_toolkit", "scripts", "providers", "jev.json")
    names = []
    try:
        with open(pin, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        for prov in (data.get("hosted") or {}).values():
            if isinstance(prov, dict) and isinstance(prov.get("key_var"), str):
                names.append(prov["key_var"])
        lg = data.get("local_gateway") or {}
        if isinstance(lg, dict) and isinstance(lg.get("key_var"), str):
            names.append(lg["key_var"])
    except (OSError, ValueError, AttributeError):
        names = []
    names = [n for n in names if re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}", n)]
    return sorted(set(names)) if names else sorted(KEY_VARS_FALLBACK)


KEY_VARS = tuple(pinned_key_vars())

# --------------------------------------------------------------- catalogue ----
CATALOGUE = {
    "layer.mode": ("enum", "shadow", {"choices": ("off", "shadow", "enforce"), "anchor": "§11.4.285"}),
    "exclusions.never_enforce": ("typelist", [], {"anchor": "§11.4.285"}),
    "calibration.floor": ("float", 0.90, {"min": 0.90, "max": 1.0, "anchor": "§11.4.285 (floor may only rise)"}),
    "calibration.min_sample": ("int", 30, {"min": 30, "max": 100000, "anchor": "§11.4.285"}),
    "calibration.cadence_days": ("int", 7, {"min": 1, "max": 7, "anchor": "§11.4.285 (weekly or more often)"}),
    "endpoints.preference": ("endpoints", ["local", "lan", "hosted"],
                             {"anchor": "§11.4.282 (local first, then LAN, then hosted)"}),
    "hosted.allowed": ("bool", True, {"anchor": "§11.4.279"}),
    "hosted.enforce": ("bool", False, {"locked": False, "anchor": "§11.4.279(E) (hosted never enforces)"}),
    "keys.discovery_consent": ("bool", True, {"locked": True,
                                              "anchor": "§11.4.279(E) (auto-discovery has no per-project opt-out)"}),
    "keys.var_names": ("keyvars", list(KEY_VARS), {"locked": list(KEY_VARS),
                                                   "anchor": "§11.4.279(E)(1) (names come from the provider pin)"}),
    "llmctl.clone_consent": ("bool", False, {"anchor": "§11.4.281"}),
    "llmctl.install_consent": ("bool", False, {"anchor": "§11.4.281"}),
    "llmctl.validate_strict": ("bool", True, {"locked": True, "anchor": "§11.4.277 (STRICT validation)"}),
    "llmctl.profiles": ("profiles", [], {"anchor": "§11.4.282"}),
    "llmctl.download_profile": ("profile", "", {"anchor": "§11.4.281"}),
    "agents.settings_json_consent": ("bool", False, {"anchor": "§11.4.280"}),
    "proof.token_reduction_arm": ("enum", "on", {"choices": ("on", "off"), "locked": "on", "anchor": "§11.4.283"}),
    "proof.max_after_before_ratio": ("float", 1.0, {"min": 0.01, "max": 1.0, "anchor": "§11.4.283 (AFTER <= BEFORE)"}),
    "budget.max_usd_per_day": ("nfloat", None, {"min": 0.0, "max": 10000.0, "anchor": "§11.4.35 data"}),
    "budget.max_hosted_calls_per_hour": ("nint", None, {"min": 0, "max": 1000000, "anchor": "§11.4.35 data"}),
}
DYN_QTYPE = re.compile(r"question_types\.([a-z][a-z0-9_]{0,39})\.mode")
DYN_AGENT = re.compile(r"agents\.([a-z][a-z0-9_]{0,39})\.wiring")


def excluded_type(t):
    return any(s in t for s in EXCLUDED_STEMS)


def key_label(k):
    """A key safe to print: a known key verbatim, anything else as a short hash (§11.4.10, never echo)."""
    if isinstance(k, str):
        if k in CATALOGUE:
            return k
        m = DYN_AGENT.fullmatch(k)
        if m and m.group(1) in AGENTS:
            return k
        m = DYN_QTYPE.fullmatch(k)
        if m and not looks_secret(k):
            return k
    raw = k if isinstance(k, str) else repr(k)
    return "key#" + hashlib.sha256(raw.encode("utf-8", "replace")).hexdigest()[:12]


def spec_for(key):
    if key in CATALOGUE:
        return CATALOGUE[key]
    m = DYN_QTYPE.fullmatch(key)
    if m:
        t = m.group(1)
        extra = {"choices": ("off", "shadow", "enforce"), "anchor": "§11.4.279(E)(3)", "qtype": t}
        if excluded_type(t):
            extra["locked"] = "off"
            extra["anchor"] = "§11.4.279(E)(3) (review/merge/finding/QA/readiness/evidence/verifier are never served)"
        return ("enum", None, extra)
    m = DYN_AGENT.fullmatch(key)
    if m:
        if m.group(1) not in AGENTS:
            raise Refused("%s: agent is not one of %s (§11.4.280)" % (key_label(key), ",".join(AGENTS)))
        return ("enum", "ask", {"choices": ("ask", "consent", "declined"), "anchor": "§11.4.280"})
    if key.startswith("question_types."):
        raise Refused("%s: invalid question type key (names match [a-z][a-z0-9_]{0,39})" % key_label(key))
    raise Refused("unknown decision key %s" % key_label(key))


def redact(s):
    """Every printed message passes here: secret-shaped runs become [redacted] (§11.4.10) and control, C1 and
    bidirectional-formatting characters are shown as \\u escapes, so nothing user-supplied can reorder or hide
    terminal text (round-3 minor)."""
    s = str(s)
    for r in SECRET_RES:
        s = r.sub("[redacted]", s)
    return safe_text(s)


def _uesc(c):
    """Fixed-width escape: \\uXXXX (exactly 4 hex digits) up to U+FFFF, \\UXXXXXXXX (exactly 8) above it (round-8 m3:
    '\\u%04x' gives 5-6 digits above U+FFFF, which reads as a 4-digit escape followed by literal hex). Display
    safety, NOT a reversible encoding: a literal backslash in the input is printed as-is, so the six characters
    backslash-u-2-0-2-e in a file name print the same as an escaped U+202E (round-8 review MINOR-1). Escaping the
    backslash too was rejected: the JSON and YAML documents printed by --show would change, and messages are
    escaped in two layers (safe_text, then the emitter), which would double every backslash."""
    o = ord(c)
    return "\\u%04x" % o if o <= 0xFFFF else "\\U%08x" % o


def scrub_secrets(s):
    """Secret-shaped runs replaced by [redacted], nothing else changed (used for backup copies)."""
    for r in SECRET_RES:
        s = r.sub("[redacted]", s)
    return s


def safe_text(s):
    """Control, C1 and bidi characters as \\u escapes (a literal backslash is kept, see _uesc); NO secret scan. For validated filesystem paths and other
    engine-authored text (round-4 I-5: a 32+ character path segment with a digit is not a credential)."""
    return "".join(_uesc(c) if is_unsafe_char(c) and c not in "\n\t" else c for c in str(s))


# ---------------------------------------------------------------- emitter ----
# THE ONE OUTPUT SEAM (round-5 structural change). Every line the engine writes to stdout or stderr passes through
# _emit via emit_out()/emit_err(): each unsafe character (control, C1, bidi, line/paragraph separators, lone surrogates from
# non-UTF-8 file names) becomes a \uXXXX escape, a newline inside ONE message cannot start a forged line (only the
# message boundaries and the lines of a multi-line block are newlines), and the final encode uses backslashreplace
# so no content can raise UnicodeEncodeError (before, a non-UTF-8 name crashed AFTER the files were written).
# tests/decisions/test_round6.sh scans the engine source and fails when anything else touches sys.stdout/sys.stderr
# or calls print(). The interactive prompts write to /dev/tty with engine-authored text and redact()ed errors.
def _clean_line(s):
    return "".join(_uesc(c) if is_unsafe_char(c) and c != "\t" else c for c in s)


def _emit(stream, text, end, block=False):
    """block=False: ONE message line, so a newline inside the text is escaped like any other unsafe character and
    cannot forge a second line. block=True: a document (YAML, JSON) whose own newlines are its structure."""
    body = "\n".join(_clean_line(part) for part in str(text).split("\n")) if block \
        else _clean_line(str(text))
    enc = getattr(stream, "encoding", None) or "utf-8"
    body = (body + end).encode(enc, "backslashreplace").decode(enc, "replace")
    stream.write(body)


def emit_out(text="", end="\n"):
    _emit(sys.stdout, text, end)


def emit_block(text):
    """A multi-line document on stdout (validated YAML text or JSON); line structure kept, each line cleaned."""
    _emit(sys.stdout, text, "", block=True)


def emit_err(text="", end="\n"):
    _emit(sys.stderr, text, end)


def report_exception(exc):
    """Print the one-line failure message for an engine exception and return the exit code (the only place that
    maps exception classes to codes). Precondition text is engine-authored and its paths are validated, so it is
    only escaped; Usage/Refused text may echo user input and is also scrubbed of key-shaped runs."""
    if isinstance(exc, Usage):
        emit_err("constitution_decisions: usage: %s" % redact(exc))
        return 2
    if isinstance(exc, Precondition):
        emit_err("constitution_decisions: blocked: %s" % safe_text(exc))
        return 3
    if isinstance(exc, Refused):
        emit_err("constitution_decisions: refused: %s" % redact(exc))
        return 4
    if isinstance(exc, OSError):  # never a traceback, never an absolute path (round-3 I-B)
        emit_err("constitution_decisions: blocked: %s%s" % (
            safe_text(os.path.basename(exc.filename)) + ": " if isinstance(exc.filename, str) else "",
            exc.strerror or type(exc).__name__))
        return 3
    raise exc


INTERNAL_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,60}")


def report_internal(name):
    """THE one line for any failure the engine did not anticipate (round-6 I-1): the exception TYPE only - never its
    message (which may hold a path, user input or key material), never a traceback. Returns the exit code 1."""
    if not isinstance(name, str) or not INTERNAL_NAME_RE.fullmatch(name):
        name = "Exception"
    try:
        emit_err("constitution_decisions: internal error (%s)" % name)
    except BaseException:  # the stream itself may be gone (closed pipe, memory exhausted): nothing more to say
        pass
    return 1


def _silence_stdout():
    """After a closed pipe, point stdout at /dev/null so the interpreter's exit-time flush cannot print a second
    error. Only called from the BrokenPipe handlers."""
    try:
        dn = os.open(os.devnull, os.O_WRONLY)
        os.dup2(dn, 1)
        os.close(dn)
    except OSError:
        pass


def emit_flush():
    """Flush stdout then stderr inside the process boundary. A flush failure on stdout (closed pipe, full device)
    silences stdout so the interpreter's own exit-time flush cannot print 'Exception ignored' and exit 120, then
    re-raises for run_cli to map; a stderr failure is dropped (nowhere left to say it)."""
    out = sys.stdout
    if out is not None:
        try:
            out.flush()
        except OSError:
            _silence_stdout()
            raise
    err = sys.stderr
    if err is not None:
        try:
            err.flush()
        except (OSError, ValueError):
            pass


def install_excepthook():
    """An exception that escapes everything (including run_cli) is reported by the same one-line emitter path:
    sys.excepthook would otherwise print a full traceback with absolute paths."""
    def hook(etype, value, tb):
        if etype is not None and issubclass(etype, KeyboardInterrupt):
            return
        if etype is not None and issubclass(etype, BrokenPipeError):
            _silence_stdout()
        report_internal(getattr(etype, "__name__", "Exception"))
    sys.excepthook = hook


def check_key(key):
    """Every user-supplied key passes here first: shape, then secret-shaped segments (review B-1)."""
    if not isinstance(key, str) or not KEY_SHAPE_RE.fullmatch(key):
        raise Refused("invalid decision key %s" % key_label(key))
    if looks_secret(key):
        raise Refused("a decision key looks like key material; refused and not shown (§11.4.10)")


# Unsafe characters are decided by Unicode CATEGORY, not by a fixed list (round-6 M-2): Cc (C0, DEL, C1 controls), Cf
# (format characters: bidirectional overrides - Trojan Source, CVE-2021-42574 - zero-width joiners and spaces, word
# joiner, the U+206A-206F deprecated formats, the U+E0000 tag characters, the BOM, soft hyphen), Cs (lone surrogates:
# what os.fsdecode gives for non-UTF-8 file names, they cannot be encoded), Co (private use), Cn (unassigned and
# noncharacters) and Zl/Zp (line and paragraph separators). Ordinary text, letters, marks, symbols, emoji and the
# space separators (Zs, including U+00A0) pass. Cn follows the Unicode version of this Python's unicodedata (a
# character assigned in a newer Unicode than the interpreter knows is escaped, which is the safe direction).
UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))


def is_unsafe_char(c):
    return unicodedata.category(c) in UNSAFE_CATEGORIES


def has_control(s):
    """C0 and DEL (as before), C1 controls, bidi overrides and line/paragraph separators."""
    return any(is_unsafe_char(c) for c in s)


def looks_secret(s):
    return any(r.search(s) for r in SECRET_RES)


def check_value_text(key, value):
    items = value if isinstance(value, list) else [value]
    for it in items:
        if isinstance(it, str):
            if has_control(it):
                raise Refused("%s: control characters are not allowed in values" % key_label(key))
            if looks_secret(it):
                raise Refused("value for %s looks like key material; refused and not shown (§11.4.10)" % key_label(key))


def _bool(key, v):
    if isinstance(v, bool):
        return v
    if isinstance(v, str) and v.strip().lower() in ("true", "yes", "1", "on"):
        return True
    if isinstance(v, str) and v.strip().lower() in ("false", "no", "0", "off"):
        return False
    raise Refused("%s expects true or false" % key_label(key))


def _list(key, v):
    if isinstance(v, list):
        return v
    if v is None:
        return []
    if isinstance(v, str):
        return [x.strip() for x in v.split(",") if x.strip() != ""]
    raise Refused("%s expects a list" % key_label(key))


# Input grammar for numbers given as TEXT (--set, --answers strings, TTY): ASCII digits only, an optional sign, for
# floats a decimal point and an exponent. Underscores, hex, non-ASCII digits, nan/inf and thousands separators are
# refused (round-4 minor: int()/float() accept far more than the documented grammar). Native YAML numbers pass.
_INT_RE = re.compile(r"[+-]?[0-9]{1,15}")
_FLOAT_RE = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]{1,4})?")


def _num(key, v, kind, extra):
    try:
        if isinstance(v, bool):
            raise ValueError
        if isinstance(v, str):
            v = v.strip()
            if not (_INT_RE if kind in ("int", "nint") else _FLOAT_RE).fullmatch(v):
                raise ValueError
        n = int(v) if kind in ("int", "nint") else float(v)
        if kind in ("int", "nint") and isinstance(v, float) and v != int(v):
            raise ValueError
    except (TypeError, ValueError, OverflowError):
        raise Refused("%s expects a number" % key_label(key))
    if n != n or n < extra["min"] or n > extra["max"]:
        raise Refused("%s must be between %s and %s (%s)" % (key_label(key), extra["min"], extra["max"], extra["anchor"]))
    return n


def normalize(key, raw):
    """Return the typed value for key, or raise Refused. Never echoes the raw value or an unknown key."""
    check_key(key)
    kind, _default, extra = spec_for(key)
    check_value_text(key, raw)
    kl = key_label(key)
    if kind == "enum":
        v = raw
        if isinstance(v, bool):  # YAML 1.1 reads off/on as booleans
            v = "on" if v else "off"
        if not isinstance(v, str) or v.strip() not in extra["choices"]:
            raise Refused("%s must be one of %s" % (kl, "|".join(extra["choices"])))
        v = v.strip()
    elif kind == "bool":
        v = _bool(key, raw)
    elif kind in ("int", "float"):
        v = _num(key, raw, kind, extra)
    elif kind in ("nint", "nfloat"):
        v = None if raw is None or (isinstance(raw, str) and raw.strip().lower() in ("null", "none", "")) \
            else _num(key, raw, kind, extra)
    elif kind == "profile":
        v = "" if raw is None else raw
        if not isinstance(v, str) or (v != "" and not PROFILE_RE.fullmatch(v)):
            raise Refused("%s must be a profile name [A-Za-z0-9][A-Za-z0-9._-]* or empty" % kl)
    elif kind in ("profiles", "typelist", "keyvars", "endpoints"):
        v = _list(key, raw)
        for it in v:
            if not isinstance(it, str):
                raise Refused("%s expects a list of names" % kl)
        if len(set(v)) != len(v):
            raise Refused("%s has duplicate entries" % kl)
        if kind == "profiles" and any(not PROFILE_RE.fullmatch(x) for x in v):
            raise Refused("%s entries must be profile names" % kl)
        if kind == "typelist" and any(not TYPE_RE.fullmatch(x) for x in v):
            raise Refused("%s entries must be question type names" % kl)
        if kind == "keyvars":
            if any(x not in KEY_VARS for x in v):
                raise Refused("%s entries must be among %s (names only)" % (kl, ",".join(KEY_VARS)))
            v = [x for x in KEY_VARS if x in v]
        if kind == "endpoints":
            if not v or any(x not in ENDPOINT_ORDER for x in v):
                raise Refused("%s must be a non-empty subset of local,lan,hosted" % kl)
            if [x for x in ENDPOINT_ORDER if x in v] != v or "local" not in v:
                raise Refused("%s must keep local and the order local, lan, hosted (%s)" % (kl, extra["anchor"]))
    else:  # pragma: no cover
        raise Refused("unsupported kind for %s" % kl)
    if "locked" in extra and v != extra["locked"]:
        raise Refused("%s is locked by the constitution to %s; a local override may not weaken it (%s)"
                      % (kl, json.dumps(extra["locked"]), extra["anchor"]))
    if "qtype" in extra and v == "enforce" and extra["qtype"] not in ENFORCE_ELIGIBLE:
        raise Refused("%s: enforce is allowed only for %s (default-deny; §11.4.279(E)(3), §11.4.285)"
                      % (kl, ",".join(ENFORCE_ELIGIBLE)))
    return v


def defaults():
    return {k: (list(s[1]) if isinstance(s[1], list) else s[1]) for k, s in CATALOGUE.items()}


def check_contradictions(eff):
    """List of contradiction messages in an effective map (empty when consistent). Never raises: callers decide
    whether a contradiction is a report (every read and recovery path) or a refusal (a write that creates it)."""
    out = []
    mode = eff.get("layer.mode")
    never = set(eff.get("exclusions.never_enforce") or [])
    for k, v in eff.items():
        m = DYN_QTYPE.fullmatch(k)
        if m and v == "enforce":
            if mode != "enforce":
                out.append("contradiction: %s is enforce but layer.mode is %s (a type enforces only when the "
                           "layer does)" % (key_label(k), mode))
            if m.group(1) in never:
                out.append("contradiction: %s is enforce but the type is in exclusions.never_enforce"
                           % key_label(k))
    if not eff.get("hosted.allowed") and "hosted" in (eff.get("endpoints.preference") or []):
        out.append("contradiction: hosted.allowed is false but endpoints.preference lists hosted")
    return out


def is_locked(key):
    try:
        return "locked" in spec_for(key)[2]
    except Refused:
        return False


def drop_locked(m):
    """Locked values are the constitution's, never stored locally (review I-4): a stored copy goes stale when the
    constitution (or the provider pin) changes and would then block every command."""
    return {k: v for k, v in m.items() if not is_locked(k)}


# Locks whose value comes from data outside this file (the claude_toolkit provider pin). A stored copy is stale by
# construction when the pin moves, so on READ it is ignored with a note instead of refused (the pin governs).
DYNAMIC_LOCKS = ("keys.var_names",)
VAR_NAME_RE = re.compile(r"[A-Z][A-Z0-9_]{0,63}")


def validate_map(m, where, reading=False, bad=None):
    """Validate a decisions map. reading=True drops locked keys (stale dynamic locks with a note). With a `bad`
    list, invalid entries are collected there (raw key, message) instead of raising: the recovery path only."""
    if not isinstance(m, dict):
        raise Refused("%s: 'decisions' must be a mapping" % where)
    out = {}
    for k, v in m.items():
        if not isinstance(k, str):
            raise Refused("%s: decision keys must be strings" % where)
        if reading and k in DYNAMIC_LOCKS and isinstance(v, list) and v \
                and all(isinstance(x, str) and VAR_NAME_RE.fullmatch(x) for x in v):
            if v != CATALOGUE[k][2]["locked"]:
                emit_err("note: %s: ignored stored %s (locked; the constitution provider pin governs it; the next "
                      "write removes it)" % (where, k))
            continue
        try:
            out[k] = normalize(k, v)
        except Refused as exc:
            if bad is None:
                raise
            bad.append((k, str(exc)))
    return drop_locked(out) if reading else out


# ------------------------------------------------------------------- YAML ----
_PLAIN = re.compile(r"[A-Za-z][A-Za-z0-9._/-]*")
_YAML_WORDS = {"y", "n", "yes", "no", "on", "off", "true", "false", "null", "none", "~"}


def yscalar(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        if _PLAIN.fullmatch(v) and v.lower() not in _YAML_WORDS:
            return v
        return json.dumps(v)
    raise ValueError("unsupported")


def yval(v):
    if isinstance(v, list):
        return "[" + ", ".join(yscalar(x) for x in v) + "]"
    return yscalar(v)


def dump_file(inherits, decisions):
    lines = ["# Local decision-model overrides (managed by constitution_decisions.sh).",
             "# These inherit from the constitution (§11.4.35). Locked constitution rules cannot be weakened here;",
             "# the other decisions choose among options the constitution permits. Change this file with the",
             "# wizard; a hand edit is detected."]
    if decisions.get("layer.mode") == "off":
        lines += ["# layer.mode: off = no enforcement and no bootstrap command printed by the wizard. It conflicts with",
                  "# §11.4.279(E) (a present key MUST be served in shadow) and stands only until an operator waiver",
                  "# is recorded (§11.4.271)."]
    lines += ["schema_version: 1", "inherits: %s" % yscalar(inherits)]
    if not decisions:
        lines.append("decisions: {}")
    else:
        lines.append("decisions:")
        for k in sorted(decisions):
            if not KEY_SHAPE_RE.fullmatch(k) or looks_secret(k) or is_locked(k):
                raise Refused("internal: refusing to dump an invalid key %s" % key_label(k))
            lines.append("  %s: %s" % (k, yval(decisions[k])))
    text = "\n".join(lines) + "\n"
    # round-trip: the text we are about to write must parse back to exactly the validated map
    data = load_yaml_text(text, "dumped decisions")
    back = parse_override_data(data, "dumped decisions")
    if back != decisions or data.get("inherits") != inherits or text.count("\n") != len(lines):
        raise Refused("internal: the dumped decisions file did not round-trip; nothing written")
    return text


def load_yaml_text(text, where):
    try:
        import yaml  # noqa: WPS433 (PyYAML; precondition)
    except ImportError:
        raise Precondition("PyYAML (python3-yaml) is required")
    try:
        data = yaml.safe_load(text)
    except Exception:
        raise Refused("%s is not valid YAML" % where)
    return data


def parse_override_data(data, where, bad=None):
    if not isinstance(data, dict):
        raise Refused("%s must be a mapping" % where)
    extra = set(data) - {"schema_version", "inherits", "decisions"}
    if extra:
        raise Refused("%s has unknown top-level keys: %s" % (where, ",".join(sorted(key_label(k) for k in extra))))
    sv = data.get("schema_version")
    if type(sv) is not int or sv != 1:
        raise Refused("%s: schema_version must be the integer 1" % where)
    inh = data.get("inherits")
    if not isinstance(inh, str) or not INHERITS_RE.fullmatch(inh) or ".." in inh.split("/") or looks_secret(inh):
        raise Refused("%s: inherits must be a relative constitution path" % where)
    return validate_map(data.get("decisions") or {}, where, reading=True, bad=bad)


def parse_override_file(path, where, bad=None):
    text = read_text(path, where)
    data = load_yaml_text(text, where)
    return text, parse_override_data(data, where, bad), data.get("inherits")


def parse_answers(path):
    data = load_yaml_text(read_text(path, "answers file"), "answers file")
    if data is None:
        return {}
    if isinstance(data, dict) and "decisions" in data and set(data) <= {"decisions", "schema_version", "inherits"}:
        data = data.get("decisions") or {}
    return validate_map(data, "answers file")


# ------------------------------------------------------------- filesystem ----
_CFG_ESC = {"n": "\n", "t": "\t", "b": "\b", "\\": "\\", '"': '"'}


def _cfg_value(text, j):
    """Value part of a git-config line starting at index j (after '='); returns (value, index after the line)."""
    n, buf, pend, inq = len(text), [], [], False
    while j < n:
        c = text[j]
        if c == "\n":
            j += 1
            break
        if c == "\\" and j + 1 >= n:  # a lone backslash at the very end of the file is dropped (git)
            j += 1
            break
        if c == "\\" and j + 1 < n:
            nx = text[j + 1]
            if nx == "\n":
                j += 2
                continue
            if nx == "\r" and text[j + 2:j + 3] == "\n":
                j += 3
                continue
            buf.extend(pend)
            pend = []
            buf.append(_CFG_ESC.get(nx, nx))
            j += 2
            continue
        if c == '"':
            if not inq:
                buf.extend(pend)
            pend = []
            inq = not inq
            j += 1
            continue
        if inq:
            buf.append(c)
        elif c in "#;":
            while j < n and text[j] != "\n":
                j += 1
            continue
        elif c == "\r" and text[j + 1:j + 2] == "\n":
            pass
        elif c in " \t":
            if buf:
                pend.append(c)
        else:
            buf.extend(pend)
            pend = []
            buf.append(c)
        j += 1
    return "".join(buf), j


def gitmodules_paths(text):
    """Values of every `path` key in every [submodule ...] section of a .gitmodules text (git-config grammar)."""
    if text.startswith("\ufeff"):  # git strips a UTF-8 byte-order mark at the start of the file (round-6 M-1)
        text = text[1:]
    res, in_sub, i, n = [], False, 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c in "#;":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "[":
            j = i + 1
            name = ""
            while j < n and text[j] not in "] \t\"\n":
                name += text[j]
                j += 1
            while j < n and text[j] in " \t":
                j += 1
            if j < n and text[j] == '"':
                j += 1
                while j < n and text[j] not in '"\n':
                    j += 2 if text[j] == "\\" else 1
                if j < n and text[j] == '"':
                    j += 1
            while j < n and text[j] in " \t":
                j += 1
            if j < n and text[j] == "]":
                j += 1
            # `[submodule "x"]` and the legacy dotted form `[submodule.x]` / `[Submodule.X.y]` (section + lowercased
            # subsection); a bare `[submodule]` is kept (a superset of git, which gives it no `.path` key: more is
            # refused, never less)
            nm = name.lower()
            in_sub = nm == "submodule" or nm.startswith("submodule.")
            i = j
        else:
            j = i
            while j < n and (text[j].isalnum() or text[j] == "-"):
                j += 1
            key = text[i:j].lower()
            if j == i:  # not a key: skip the line
                while j < n and text[j] != "\n":
                    j += 1
                i = j
                continue
            while j < n and text[j] in " \t":
                j += 1
            if j < n and text[j] == "=":
                val, j = _cfg_value(text, j + 1)
                val = val.split("\0", 1)[0]  # git keeps a config value only up to the first NUL (round-8 m2)
                if in_sub and key == "path" and val:
                    res.append(val)
            else:
                while j < n and text[j] != "\n":
                    j += 1
            i = j
    return res


def home_dirs():
    """Real paths of the home directory as $HOME names it AND as the passwd database names it (round-5 minor)."""
    hs = set()
    h = os.environ.get("HOME")
    if h and os.path.isabs(h):  # a relative $HOME would name a cwd-relative directory (round 11)
        hs.add(os.path.realpath(h))
    try:
        hs.add(os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir))
    except (KeyError, OSError):
        pass
    return hs


class Project:
    def __init__(self, root):
        if not root or not os.path.isdir(root):
            raise Precondition("project root is not a directory")
        self.root = os.path.realpath(root)
        if ".git" in self.root.split(os.sep):
            raise Precondition("project root is inside a .git directory; refused")
        self.inh_override = None
        self.inh_recorded = False  # inh_override came from .constitution/decisions.yml, not from --inherits
        self.cdir = os.path.join(self.root, ".constitution")
        self.dfile = os.path.join(self.cdir, "decisions.yml")
        self.sfile = os.path.join(self.cdir, "decisions.sha256")
        self.ifile = os.path.join(self.cdir, "decisions.intent")

    def contains(self, p):
        return p == self.root or p.startswith(self.root + os.sep)

    def rel(self, p):
        """THE display form of a path inside the project (round-5 structural change): relative to the root, and a
        key-shaped result is never shown (the same policy `inside` applies to arguments, applied to resolved paths)."""
        r = os.path.relpath(p, self.root)
        return "<path hidden: key-shaped>" if looks_secret(r) else r

    def rel_own(self, p):
        """Relative path of a location the wizard itself generated (backup directories): plain, no key-shape policy
        (a joined 'dir/stamp-decisions' run is long enough to look like a token and is not user data)."""
        return os.path.relpath(p, self.root)

    def guard(self, what, check_foreign):
        """Callable for atomic_write: re-checked immediately before the replace, so a parent directory swapped for a
        symlink (or moved into another repository) after validation is caught at the last moment (round-5 TOCTOU).
        Round 10: atomic_write creates the temp file and renames through a descriptor of the parent opened before this
        guard, and checks the path still names that inode, so a swapped parent is refused or harmless. This guard's
        remaining unique duties are the realpath comparison (a parent MOVED, with a symlink left at the old name, keeps
        its inode) and the .git-appears-in-the-parent case. RESIDUALS (documented in the plan): the held directory
        could be moved between this check and rename(2); that needs a writer with access to the project."""
        def _g(path):
            d = os.path.dirname(path)
            if os.path.realpath(d) != d or not self.contains(d):
                raise Precondition("%s: its parent directory changed while this run was working (it now resolves "
                                   "elsewhere); nothing more written, re-run to apply" % what)
            if check_foreign:
                self.refuse_foreign(path, what)
        return _g

    def inside(self, path, allow_link=False):
        """Resolve a project-relative or absolute path; refuse paths outside the project, secret-shaped paths
        and (unless allow_link) symlinked targets. Never echoes a refused path."""
        if not isinstance(path, str) or path == "" or has_control(path):
            raise Precondition("invalid path")
        p = path if os.path.isabs(path) else os.path.join(self.root, path)
        p = os.path.normpath(p)
        parent = os.path.realpath(os.path.dirname(p))
        if not self.contains(parent):
            raise Precondition("path resolves outside the project (refused)")
        p = os.path.join(parent, os.path.basename(p))
        if looks_secret(os.path.relpath(p, self.root)):
            raise Precondition("path looks like key material; refused and not shown (§11.4.10)")
        if os.path.islink(p) and not allow_link:
            raise Precondition("%s is a symlink; refused" % self.rel(p))
        return p

    def gitmodule_paths(self):
        """Real paths of every submodule path named in .gitmodules, read with git-config grammar (case-insensitive
        keys, quoted values, trailing ; or # comments, CRLF, a key on the section line). The bytes are decoded with
        surrogateescape so a non-UTF-8 comment or path never refuses the run (round-5 minor)."""
        gp = os.path.join(self.root, ".gitmodules")
        try:
            if os.path.exists(gp) and not os.path.isfile(gp):
                raise Precondition(".gitmodules is not a regular file; refused")
            with open(gp, "rb") as fh:
                raw = fh.read(MAX_READ + 1)
        except FileNotFoundError:
            return []
        except PermissionError:
            raise Precondition(".gitmodules is not readable (permission denied)")
        except (IsADirectoryError, NotADirectoryError):
            return []
        if len(raw) > MAX_READ:
            raise Refused(".gitmodules is larger than %d characters; not touched" % MAX_READ)
        return [os.path.realpath(os.path.join(self.root, m))
                for m in gitmodules_paths(raw.decode("utf-8", "surrogateescape"))]

    def foreign(self, p):
        """True when the (resolved) path p belongs to something other than this project: a .gitmodules path, the
        inherited constitution (submodules/constitution, ./constitution, or an explicit --inherits path), or any
        directory below the root that has its own .git (a checked-out gitlink or a nested repository)."""
        roots = list(self.gitmodule_paths())
        cands = ["submodules/constitution", "constitution"] + ([self.inh_override] if self.inh_override else [])
        for c in cands:
            if c and c != ".":
                roots.append(os.path.realpath(os.path.join(self.root, c)))
        if any(p == q or p.startswith(q + os.sep) for q in roots if q != self.root):
            return True
        d = os.path.dirname(p)
        while d != self.root and self.contains(d):
            if os.path.lexists(os.path.join(d, ".git")):
                return True
            d = os.path.dirname(d)
        return False

    def refuse_foreign(self, p, what):
        if self.foreign(p):
            raise Foreign("%s: %s resolves inside a git submodule, another repository or the inherited "
                          "constitution; the wizard never writes there" % (what, self.rel(p)))

    def is_home_like(self):
        """The root is a home directory or an ancestor of one (not a project root in the user-scope sense)."""
        return any(h == self.root or h.startswith(self.root.rstrip(os.sep) + os.sep) for h in home_dirs())

    def inherits_dir_ok(self, rel_path):
        """A recorded or explicit --inherits value must name an existing directory inside the project."""
        if rel_path == ".":
            return True
        real = os.path.realpath(os.path.join(self.root, rel_path))
        return os.path.isdir(real) and real != self.root and self.contains(real)

    def recorded_inherits(self):
        """The inherits value recorded in .constitution/decisions.yml when it names an existing directory inside
        the project (round-5: later writes without --inherits keep it). Never raises; unreadable or invalid = None.
        A recorded '.' counts only in the constitution repository itself."""
        try:
            if os.path.islink(self.cdir) or os.path.islink(self.dfile) or not os.path.isfile(self.dfile):
                return None
            data = load_yaml_text(read_text(self.dfile, ".constitution/decisions.yml"), "decisions.yml")
            inh = data.get("inherits") if isinstance(data, dict) else None
            if not isinstance(inh, str) or not INHERITS_RE.fullmatch(inh) or ".." in inh.split("/") \
                    or looks_secret(inh):
                return None
            if inh == ".":
                return "." if self.root == CONST_ROOT else None
            return inh if self.inherits_dir_ok(inh) else None
        except (Refused, Precondition, OSError):
            return None

    def require_inherited(self, explicit):
        """Precondition for any project write (round-4 I-3): the project root must be inside a git repository, must
        hold or name (--inherits, or the path recorded by an earlier wizard run) an inherited constitution, and is
        never a home directory unless --inherits was given explicitly. A RECORDED path only replaces the
        constitution check; it never waives the home or repository checks (a crafted decisions.yml cannot)."""
        self.inh_override = explicit or self.inh_override
        if explicit:
            return
        if self.root in home_dirs():
            raise Precondition("the project root is the HOME directory; pass --inherits PATH to confirm this is "
                               "a project (refused)")
        d, in_repo = self.root, False
        while True:
            if os.path.lexists(os.path.join(d, ".git")):  # a directory, or a FILE (worktree / submodule checkout)
                in_repo = True
                break
            nd = os.path.dirname(d)
            if nd == d:
                break
            d = nd
        if not in_repo:
            raise Precondition("the project root is not inside a git repository; pass --inherits PATH to "
                               "confirm this is a project (refused)")
        if CONST_ROOT != self.root and not self.inh_recorded \
                and not any(os.path.isdir(os.path.join(self.root, c))
                            for c in ("submodules/constitution", "constitution")):
            raise Precondition("no inherited constitution found (submodules/constitution or ./constitution); "
                               "pass --inherits PATH to record one explicitly (refused)")

    def forbidden(self, p):
        rel = os.path.relpath(p, self.root)
        return rel == "." or any(part in FORBIDDEN_TOP for part in rel.split(os.sep))

    def user_target(self, path, what):
        """inside() plus: never inside .git/, .constitution/ or .constitution-install-backup/ (any depth)."""
        p = self.inside(path)
        if self.forbidden(p):
            raise Precondition("%s may not target .git/, .constitution/ or .constitution-install-backup/" % what)
        self.refuse_foreign(p, what)
        return p

    def doc_path(self, name, what):
        """A doc target. An in-project symlink is RESOLVED to its target (review I-6): the target must be a
        regular file (or absent) inside the project and outside the forbidden directories; escapes are refused."""
        p = self.inside(name, allow_link=True)
        if os.path.islink(p):
            real = os.path.realpath(p)
            if not self.contains(real) or self.forbidden(real) or (os.path.exists(real) and not os.path.isfile(real)):
                raise Precondition("%s is a symlink that leaves the project or points at a forbidden or non-regular "
                                   "target; refused" % self.rel(p))
            if looks_secret(os.path.relpath(real, self.root)):  # same policy as a direct argument (round-5 I-2)
                raise Precondition("%s is a symlink whose target path looks like key material; refused and not "
                                   "shown (§11.4.10)" % self.rel(p))
            p = real
        elif self.forbidden(p):
            raise Precondition("%s may not target .git/, .constitution/ or .constitution-install-backup/" % what)
        if os.path.exists(p) and not os.path.isfile(p):
            raise Precondition("%s is not a regular file; refused" % self.rel(p))
        self.refuse_foreign(p, what)
        return p

    def inherits(self):
        if self.inh_override:
            return self.inh_override
        for cand in ("submodules/constitution", "constitution"):
            if os.path.isdir(os.path.join(self.root, cand)):
                return cand
        if CONST_ROOT == self.root:
            return "."
        return "submodules/constitution"


def user_file():
    f = os.environ.get("CONSTITUTION_DECISIONS_USER_FILE")
    if f:
        # A relative value would resolve against the caller's working directory (often a project tree);
        # the user layer must never land there by accident.
        if not os.path.isabs(f):
            raise Precondition("CONSTITUTION_DECISIONS_USER_FILE must be an absolute path; refused")
        return os.path.normpath(f)
    base = os.environ.get("XDG_CONFIG_HOME")
    if not base or not os.path.isabs(base):  # XDG spec: a relative value is invalid and MUST be ignored (round 11)
        h = os.path.expanduser("~")
        if not os.path.isabs(h):  # a relative $HOME would resolve against the caller's cwd: use the passwd entry
            try:
                h = pwd.getpwuid(os.getuid()).pw_dir
            except (KeyError, OSError):
                raise Precondition("cannot determine an absolute home directory; refused")
        base = os.path.join(h, ".config")
    return os.path.join(base, "constitution", "decisions.yml")


def sha_text(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()


MAX_READ = 4 * 1024 * 1024  # characters; decision files, answers and docs above this are refused (never slurped)


def read_text(p, where=None):
    """Read UTF-8 text keeping line endings (CRLF preserved). None when absent. Reads at most MAX_READ + 1
    characters, so an endless stream (FIFO, /dev/zero) or a huge file is refused instead of exhausting memory."""
    label = where or os.path.basename(p)
    try:
        if os.path.exists(p) and not os.path.isdir(p) and not os.path.isfile(p):
            raise Precondition("%s is not a regular file (device, FIFO or socket); refused" % label)
        with open(p, "r", encoding="utf-8", newline="") as fh:
            t = fh.read(MAX_READ + 1)
    except FileNotFoundError:
        return None
    except PermissionError:
        raise Precondition("%s is not readable (permission denied)" % label)
    except UnicodeDecodeError:
        raise Refused("%s is not UTF-8 text; not touched" % label)
    except IsADirectoryError:
        raise Precondition("%s is a directory" % label)
    except NotADirectoryError:
        raise Precondition("%s: a parent path is not a directory" % label)
    if len(t) > MAX_READ:
        raise Refused("%s is larger than %d characters; not touched" % (label, MAX_READ))
    return t


def test_delay(var):
    """Test-only seam (CONSTITUTION_DECISIONS_TEST=1): widens a race window so tests can exercise it."""
    if os.environ.get("CONSTITUTION_DECISIONS_TEST") == "1":
        try:
            delay = float(os.environ.get(var, "0") or 0)
        except ValueError:
            delay = 0
        if delay > 0:
            time.sleep(delay)


def new_file_mode(base=0o666):
    """Mode for a NEW file: honours the process umask (a 077 umask keeps it private), like any other tool."""
    um = os.umask(0)
    os.umask(um)
    return base & ~um


def _open_parent(d, nofollow):
    """The target's parent as a directory DESCRIPTOR (round-10 finding 6). The temp file is created in it and renamed
    through it, so a swap of the path (a parent replaced by a symlink into another repository) after this point can
    no longer redirect the rename. nofollow=True (guarded project writes) refuses a parent that is itself a symlink."""
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0) | (os.O_NOFOLLOW if nofollow else 0)
    try:
        return os.open(d, flags)
    except OSError:
        raise Precondition("%s changed while this run was working or is not a plain directory; refused"
                           % safe_text(os.path.basename(d)))


def _same_parent(dfd, d):
    """The path d still names the directory the descriptor holds (same device and inode)."""
    try:
        a, b = os.stat(d), os.fstat(dfd)
    except OSError:
        raise Precondition("%s changed while this run was working; nothing more written, re-run to apply"
                           % safe_text(os.path.basename(d)))
    if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
        raise Precondition("%s changed while this run was working (its parent no longer names the directory that was "
                           "opened); nothing more written, re-run to apply" % safe_text(os.path.basename(d)))


def atomic_write(path, text, expect=None, base_mode=0o666, guard=None):
    """Write via a temp file and rename. `expect` is the content the plan was computed from (None = the file must
    still be absent, False = no check): it is re-read just before the rename, so an edit made by someone else
    during the run is never overwritten (lost update). Round 10: the temp file is created and the rename done
    THROUGH A DESCRIPTOR of the parent directory opened before the guard, and the guard runs after the open and is
    followed by a same-inode check, so a parent swapped at any point is either refused or harmless (the data goes to
    the directory that was validated). RESIDUAL: the directory the descriptor holds could itself be MOVED (renamed)
    into another repository after the guard; that needs a writer with access to the project and is not closed."""
    d = os.path.dirname(path)
    name = os.path.basename(path)
    mode = None
    if os.path.exists(path):
        mode = os.stat(path).st_mode & 0o7777
    dfd = _open_parent(d, nofollow=guard is not None)
    tmpname = None
    try:
        while True:
            tmpname = ".%s.tmp.%s" % (name, secrets.token_hex(6))
            try:
                fd = os.open(tmpname, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0),
                             0o600, dir_fd=dfd)
                break
            except FileExistsError:
                continue
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
            os.fchmod(fh.fileno(), mode if mode is not None else new_file_mode(base_mode))
        test_delay("CONSTITUTION_DECISIONS_TEST_WRITE_DELAY")
        if expect is not False and read_text(path) != expect:
            raise Refused("%s changed while this run was working; nothing more written (re-run to apply)"
                          % os.path.basename(path))
        if guard is not None:
            guard(path)  # last path-based check before the rename (TOCTOU); raises Precondition
        if name == os.environ.get("CONSTITUTION_DECISIONS_TEST_POSTGUARD_NAME", "\0"):
            test_delay("CONSTITUTION_DECISIONS_TEST_POSTGUARD_DELAY")  # test-only: widen the guard-to-check window
        _same_parent(dfd, d)
        if name == os.environ.get("CONSTITUTION_DECISIONS_TEST_POSTCHECK_NAME", "\0"):
            test_delay("CONSTITUTION_DECISIONS_TEST_POSTCHECK_DELAY")  # test-only: widen the check-to-rename window
        os.replace(tmpname, name, src_dir_fd=dfd, dst_dir_fd=dfd)
        tmpname = None
        os.fsync(dfd)
    finally:
        try:
            if tmpname is not None:
                try:
                    os.unlink(tmpname, dir_fd=dfd)
                except FileNotFoundError:
                    pass
        finally:
            os.close(dfd)


def preflight(targets, rel):
    """Before the FIRST write of a run: every target directory must exist and be writable on a writable file
    system with room for the new content, and every existing target must be a single-link, writable regular file.
    A read-only file (0444) is refused rather than silently replaced (os.replace ignores the file's own mode), and
    a hard-linked file is refused because replacing it would silently split it from its other names."""
    need = {}
    for path, text in targets:
        d = os.path.dirname(path)
        need[d] = need.get(d, 0) + len(text.encode("utf-8")) + 4096
        if os.path.lexists(path):
            st = os.lstat(path)
            if not stat.S_ISREG(st.st_mode):
                raise Precondition("%s is not a regular file; refused" % rel(path))
            if st.st_nlink > 1:
                raise Precondition("%s has %d hard links; replacing it would split them (refused; copy it to a "
                                   "single file first)" % (rel(path), st.st_nlink))
            if not os.access(path, os.W_OK):
                raise Precondition("%s is read-only; refused (make it writable to let the wizard update it)"
                                   % rel(path))
    for d, size in need.items():
        if not os.path.isdir(d):
            raise Precondition("%s: the directory does not exist" % rel(d))
        try:
            vfs = os.statvfs(d)
        except OSError as exc:
            raise Precondition("%s: cannot inspect the file system (%s)" % (rel(d), exc.strerror))
        if vfs.f_flag & getattr(os, "ST_RDONLY", 1):
            raise Precondition("%s is on a read-only file system; nothing written" % rel(d))
        if not os.access(d, os.W_OK | os.X_OK):
            raise Precondition("%s is not writable; nothing written" % rel(d))
        if vfs.f_bavail * vfs.f_frsize < size + 1024 * 1024:
            raise Precondition("%s: not enough free space; nothing written" % rel(d))


def clean_stale_temps(dirs_names):
    for d, name in dirs_names:
        try:
            entries = os.listdir(d)
        except OSError:
            continue
        rx = re.compile(r"\." + re.escape(name) + r"\.tmp\.[0-9a-f]{12}")  # exactly atomic_write's form (round 11)
        for e in entries:
            fp = os.path.join(d, e)
            if rx.fullmatch(e) and os.path.isfile(fp) and not os.path.islink(fp):
                os.unlink(fp)  # single file, never recursive


def make_dir(d, mode=0o755):
    if os.path.islink(d):
        raise Precondition("%s is a symlink; refused" % os.path.basename(d))
    if os.path.exists(d) and not os.path.isdir(d):
        raise Precondition("%s exists and is not a directory; refused" % os.path.basename(d))
    os.makedirs(d, mode=mode, exist_ok=True)


def acquire_lock(d):
    """flock on <d>/.decisions.lock opened with O_NOFOLLOW. Returns fd, or None when another run holds it."""
    lp = os.path.join(d, ".decisions.lock")
    if os.path.islink(lp):
        raise Precondition("lock file is a symlink; refused")
    try:
        fd = os.open(lp, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), 0o644)
    except OSError:
        raise Precondition("cannot open the lock file safely; refused")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return None
    return fd


# ------------------------------------------------------------- doc blocks ----
def render_block(inherits, decisions):
    tool_rel = "scripts/decisions/constitution_decisions.sh" if inherits == "." else \
        "%s/scripts/decisions/constitution_decisions.sh" % inherits
    out = [BEGIN + " (managed by constitution_decisions.sh; text inside is regenerated) -->",
           "## Decision-model choices (local overrides)", "",
           "This project inherits from %s (§11.4.35). Locked constitution rules cannot be weakened by these "
           "decisions; the other decisions choose among options the constitution permits. Source of truth: "
           "`.constitution/decisions.yml`; change it with `%s`." % (inherits, tool_rel), ""]
    if decisions.get("layer.mode") == "off":
        out += ["`layer.mode: off` means no enforcement and no bootstrap command printed by the wizard. It "
                "conflicts with §11.4.279(E) (a present key MUST be served in shadow; no separate enablement "
                "flag) and stands only until an operator waiver is recorded.", ""]
    if decisions:
        out.append("Local overrides:")
        for k in sorted(decisions):
            out.append("- `%s`: %s" % (k, yval(decisions[k])))
    else:
        out.append("All decisions are inherited from the constitution; there are no local overrides.")
    out.append(END + " -->")
    return "\n".join(out) + "\n"


_MD_LINE = re.compile(r"[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+\Z")


def md_lines(text):
    """Markdown lines (CommonMark: only LF, CRLF and CR end a line; str.splitlines would also split on U+2028,
    form feed and others, which a Markdown reader does not)."""
    return _MD_LINE.findall(text)


def scan_markers(lines):
    """(begin_indexes, end_indexes, open_fence): exact whole-line markers outside fenced code blocks (review I-3,
    round-3 B-A). open_fence is the 0-based line index of a fence still open at the end of the document, else None:
    any text appended after it would be code, invisible to the next scan, so callers refuse instead of appending."""
    b, e, fence, fence_at = [], [], None, None
    for i, l in enumerate(lines):
        t = l.rstrip("\r\n")
        if fence is None:
            m = FENCE_OPEN_RE.fullmatch(t)
            if m and not (m.group(2)[0] == "`" and "`" in m.group(3)):
                fence, fence_at = m.group(2), i
                continue
        else:
            m = FENCE_CLOSE_RE.fullmatch(t)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence, fence_at = None, None
            continue
        if BEGIN_RE.fullmatch(t):
            b.append(i)
        elif END_RE.fullmatch(t):
            e.append(i)
    return b, e, fence_at


def has_markers(text):
    b, e, _f = scan_markers(md_lines(text))
    return bool(b or e)


def has_block(text, where):
    b, e, _f = scan_markers(md_lines(text))
    if not b and not e:
        return False
    if len(b) != 1 or len(e) != 1 or e[0] < b[0]:
        raise Refused("%s has duplicate or unbalanced constitution-decisions markers; not touched" % where)
    return True


def apply_block(text, block, where):
    """Insert or replace the managed block. Refuses (doc untouched) when the structure is ambiguous, and verifies
    the result: it must hold exactly ONE live block equal to `block`, so a parser disagreement can never make a
    write invisible to the next run (and the doc can never accumulate blocks, round-3 B-A)."""
    nl = "\r\n" if "\r\n" in text else "\n"
    if nl != "\n":
        block = block.replace("\n", nl)
    lines = md_lines(text)
    b, e, open_fence = scan_markers(lines)
    if not b and not e:
        if open_fence is not None:
            raise Refused("%s ends inside an unclosed code fence (opened on line %d); a block appended there would "
                          "be code. Close the fence, then re-run; not touched" % (where, open_fence + 1))
        sep = "" if text.endswith("\n") or text == "" else nl
        lead = nl if text.strip() else ""
        out = text + sep + lead + block
    elif len(b) != 1 or len(e) != 1 or e[0] < b[0]:
        raise Refused("%s has duplicate or unbalanced constitution-decisions markers; not touched" % where)
    else:
        out = "".join(lines[:b[0]]) + block + "".join(lines[e[0] + 1:])
    ol = md_lines(out)
    b2, e2, _f2 = scan_markers(ol)
    if len(b2) != 1 or len(e2) != 1 or e2[0] < b2[0] or "".join(ol[b2[0]:e2[0] + 1]) != block:
        raise Refused("%s: the managed block would not be recognised after writing (ambiguous Markdown structure); "
                      "not touched" % where)
    return out


def doc_targets(proj, extra_docs):
    """[(name, path)]: existing default docs plus validated --doc targets."""
    out, seen = [], set()
    for name in DEFAULT_DOCS:
        if os.path.lexists(os.path.join(proj.root, name)):
            try:
                p = proj.doc_path(name, name)
            except Foreign:
                emit_err("note: skipped %s (it resolves into a git submodule, another repository or the inherited "
                      "constitution; the wizard never writes there)" % name)
                continue
            if os.path.exists(p) and p not in seen:  # a symlink to another doc is written once (de-duplicated)
                seen.add(p)
                out.append((os.path.relpath(p, proj.root), p))
    for name in extra_docs:
        p = proj.doc_path(name, "--doc")
        if not p.lower().endswith((".md", ".markdown")):
            t = read_text(p, "--doc target")
            if t is None or not has_markers(t):
                raise Precondition("--doc %s: only Markdown files, or files that already carry the "
                                   "constitution-decisions markers" % proj.rel(p))
        if p not in seen:
            seen.add(p)
            out.append((os.path.relpath(p, proj.root), p))
    return out


# ------------------------------------------------------------------ core ----
# Every JEV_BOOTSTRAP_* variable that can become a decision; all need --accept-env (review I5, I-8).
CONSENT_ENV = ("JEV_BOOTSTRAP_MODE", "JEV_BOOTSTRAP_AGENTS", "JEV_BOOTSTRAP_CONSENT", "JEV_BOOTSTRAP_ALLOW_CLONE",
               "JEV_BOOTSTRAP_INSTALL_TOOLS", "JEV_BOOTSTRAP_DOWNLOAD_PROFILE")
# The printed bootstrap command neutralises the ambient environment (review I-5, round-3 I-A). CENSUS (2026-10-30) of
# every JEV_/LLMCTL_/CLAUDE_/TYPESAFE_/OPENROUTER_/HELIX_ variable read by scripts/jev/bootstrap.sh and the scripts it
# sources or runs from scripts/jev (lib_decide.sh, lib_keys.sh, jev-calibrate.sh, jev-probe.sh). Every census name is
# UNSET in the printed command unless it is in BOOTSTRAP_PASS_ENV; decision-carrying ones are then pinned explicitly.
# tests/decisions/test_round4.sh fails when one of those scripts gains a variable missing from this list, and the
# engine also re-scans the scripts at run time (bootstrap_env_names) so a new variable is unset even before the list
# is updated. The advisory gates bootstrap runs from scripts/gates are outside the census (honest boundary).
BOOTSTRAP_ENV = (
    # bootstrap.sh switches and consents (JEV_BOOTSTRAP_NESTED skips the advisory gates; HOME = managed-clone root)
    "JEV_BOOTSTRAP_NON_INTERACTIVE", "JEV_BOOTSTRAP_DEFER", "JEV_BOOTSTRAP_CONSENT", "JEV_BOOTSTRAP_INSTALL_TOOLS",
    "JEV_BOOTSTRAP_ALLOW_CLONE", "JEV_BOOTSTRAP_DOWNLOAD_PROFILE", "JEV_BOOTSTRAP_MODE", "JEV_BOOTSTRAP_AGENTS",
    "JEV_BOOTSTRAP_NESTED", "JEV_BOOTSTRAP_HOME",
    # calibration thresholds (always pinned below: jev-calibrate.sh reads them unclamped)
    "JEV_CALIBRATE_FLOOR", "JEV_CALIBRATE_MIN_SAMPLE", "JEV_CALIBRATE_ALIAS_CMD", "JEV_CALIBRATE_ALIAS_FILE",
    # endpoints, probes, timeouts and tool sources (the pinned submodules and defaults govern, §11.4.286)
    "JEV_HOSTED_PROBE", "JEV_BASE_URL", "TYPESAFE_BASE_URL", "JEV_CA_FILE", "JEV_DETECTION_FILE",
    "JEV_DETECTION_MAX_AGE", "JEV_PINS_FILE", "JEV_CONSTITUTION_ROOT", "JEV_DOWNLOAD_TIMEOUT", "JEV_GATE_TIMEOUT",
    "JEV_PROBE_TIMEOUT", "JEV_TOOL_TIMEOUT", "JEV_KEYS_FILE_TIMEOUT", "LLMCTL_BIN", "LLMCTL_DIR", "LLMCTL_CACERT",
    "LLMCTL_DECIDE_PORT", "LLMCTL_ENDPOINT", "LLMCTL_REF_OVERRIDE", "CLAUDE_TOOLKIT_DIR",
    # validation and test seams (JEV_SKIP_VALIDATION would weaken §11.4.277 STRICT validation)
    "JEV_SKIP_VALIDATION", "JEV_TEST", "JEV_NOW_EPOCH", "JEV_X", "JEV_BEFORE_WRITE_CMD", "JEV_DECISION_PROFILES",
    "JEV_REQUIRE_VALIDATED_CMD",
)
# Kept from the environment on purpose: where state, config, evidence and the operator key file live (locations, not
# decisions), and the key variables themselves (read by NAME only, §11.4.10).
BOOTSTRAP_PASS_ENV = ("JEV_HOME", "JEV_CONFIG_DIR", "JEV_STATE_DIR", "JEV_EVIDENCE_DIR", "JEV_API_KEYS_FILE",
                      "CLAUDE_CONFIG_DIR", "TYPESAFE_API_KEY", "OPENROUTER_API_KEY", "LLMCTL_API_KEY")
BOOTSTRAP_SCRIPTS = ("bootstrap.sh", "lib_decide.sh", "lib_keys.sh", "jev-calibrate.sh", "jev-probe.sh")
ENV_REF_RE = re.compile(r"\$\{?((?:JEV|LLMCTL|CLAUDE|TYPESAFE|OPENROUTER|HELIX)_[A-Z0-9_]*)")


def env_census(jev_dir):
    """Names referenced as $NAME / ${NAME...} in the bootstrap scripts; None when a script cannot be read (blind)."""
    names = set()
    for f in BOOTSTRAP_SCRIPTS:
        try:
            with open(os.path.join(jev_dir, f), encoding="utf-8", errors="replace") as fh:
                names.update(ENV_REF_RE.findall(fh.read()))
        except OSError:
            return None
    return names


def bootstrap_env_names():
    """Names the printed command unsets: the static census plus anything a run-time re-scan finds."""
    found = env_census(os.path.join(CONST_ROOT, "scripts", "jev")) or set()
    return [n for n in BOOTSTRAP_ENV] + sorted(n for n in found if n not in BOOTSTRAP_ENV and n not in BOOTSTRAP_PASS_ENV)


def env_decisions(accept):
    env = os.environ
    out = {}
    present = [n for n in CONSENT_ENV if env.get(n)]
    if not present:
        return out
    if not accept:
        emit_err("note: ignored decisions from environment %s (pass --accept-env to record them)" % ",".join(present))
        return out
    if env.get("JEV_BOOTSTRAP_MODE"):
        out["layer.mode"] = env["JEV_BOOTSTRAP_MODE"]
    agents = env.get("JEV_BOOTSTRAP_AGENTS", "")
    if agents or env.get("JEV_BOOTSTRAP_CONSENT") == "1":
        names = list(AGENTS) if agents in ("", "all") else [a for a in agents.split(",") if a]
        for a in names:
            out["agents.%s.wiring" % a] = "consent"
    if env.get("JEV_BOOTSTRAP_ALLOW_CLONE") == "1":
        out["llmctl.clone_consent"] = True
    if env.get("JEV_BOOTSTRAP_INSTALL_TOOLS") == "1":
        out["llmctl.install_consent"] = True
    if env.get("JEV_BOOTSTRAP_DOWNLOAD_PROFILE"):
        out["llmctl.download_profile"] = env["JEV_BOOTSTRAP_DOWNLOAD_PROFILE"]
    return validate_map(out, "JEV_BOOTSTRAP_* environment")


def parse_set(items):
    out, seen = {}, set()
    for it in items:
        if "=" not in it:
            raise Usage("--set expects KEY=VALUE")
        k, v = it.split("=", 1)
        check_key(k)
        if k in seen:
            raise Usage("decision key given twice with --set")
        seen.add(k)
        out[k] = v
    return validate_map(out, "--set")


def effective(user, project):
    eff = defaults()
    src = {k: "constitution" for k in eff}
    for layer, name in ((user, "user"), (project, "project")):
        for k, v in layer.items():
            eff[k] = v
            src[k] = name
    if not eff.get("hosted.allowed") and src["endpoints.preference"] == "constitution":
        eff["endpoints.preference"] = [x for x in eff["endpoints.preference"] if x != "hosted"]
        src["endpoints.preference"] = "constitution (hosted not allowed)"
    conflicts = [{"key": k, "user": user[k], "project": project[k]}
                 for k in sorted(set(user) & set(project)) if user[k] != project[k]]
    return eff, src, conflicts


def bootstrap_command(eff, inherits):
    """(command, notes). The command implies EXACTLY the recorded consents, never more (review B3)."""
    if eff.get("layer.mode") == "off":
        return ("decision layer is off: no bootstrap command printed (conflicts with §11.4.279(E) pending an "
                "operator waiver)"), []
    path = "scripts/jev/bootstrap.sh" if inherits == "." else "%s/scripts/jev/bootstrap.sh" % inherits
    notes = []
    # env -u: no ambient variable may add consent or weaken a rule the decisions do not record (I-5, round-3 I-A);
    # the calibration thresholds are ALWAYS explicit (jev-calibrate.sh reads them without clamping).
    env = ["env"] + ["-u %s" % n for n in bootstrap_env_names()]
    if eff.get("llmctl.download_profile"):
        env.append("JEV_BOOTSTRAP_DOWNLOAD_PROFILE=%s" % eff["llmctl.download_profile"])
    env.append("JEV_CALIBRATE_FLOOR=%s" % eff["calibration.floor"])
    env.append("JEV_CALIBRATE_MIN_SAMPLE=%s" % eff["calibration.min_sample"])
    if not eff.get("hosted.allowed"):
        env.append("JEV_HOSTED_PROBE=0")
    args = ["--non-interactive"]
    if eff.get("layer.mode") == "enforce":
        args.append("--enforce")
    consent = [a for a in AGENTS if eff.get("agents.%s.wiring" % a) == "consent"]
    wired = []
    for a in consent:
        if a == "claude" and not eff.get("agents.settings_json_consent"):
            notes.append("claude not wired: jev-setup edits the claude settings.json and "
                         "agents.settings_json_consent is not recorded")
            continue
        wired.append(a)
    if wired:
        if eff.get("llmctl.clone_consent"):
            args += ["--agent", ",".join(wired), "--yes"]
        else:
            notes.append("%s not wired: bootstrap --yes (needed to edit agent homes) also grants clone consent, "
                         "and llmctl.clone_consent is not recorded" % ",".join(wired))
    if eff.get("llmctl.clone_consent"):
        args.append("--allow-clone")
    if eff.get("llmctl.install_consent"):
        args.append("--install-tools")
    return " ".join(env + ["bash", path] + args), notes


def print_bootstrap(eff, inherits, prefix):
    cmd, notes = bootstrap_command(eff, inherits)
    emit_out("bootstrap (%s): %s" % (prefix, cmd))
    for n in notes:
        emit_out("note: %s" % n)


def run_readonly(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout,
                           stdin=subprocess.DEVNULL, check=False)
        return r.returncode, r.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(type(exc).__name__)


def do_plan(eff, inherits, probe):
    print_bootstrap(eff, inherits, "printed, NOT run; bootstrap.sh has no dry-run mode")
    status = os.path.join(CONST_ROOT, "scripts", "jev", "jev-status.sh")
    if os.path.isfile(status):
        rc, out = run_readonly(["bash", status, "--json", "--no-validate"])
        mode = "unknown"
        det = "absent"
        try:
            j = json.loads(out)
            mode = j.get("mode", "unknown")
            det = "present" if j.get("detection") else "absent"
        except (ValueError, AttributeError):
            pass
        emit_out("jev-status (read-only, --no-validate): rc=%s mode=%s detection=%s" % (rc, mode, det))
    else:
        emit_out("jev-status: SKIP (scripts/jev/jev-status.sh not found)")
    if probe:
        llm = os.environ.get("LLMCTL_BIN") or shutil.which("llmctl")
        if not llm:
            emit_out("llmctl plan: SKIP (llmctl not found)")
        else:
            rc, out = run_readonly([llm, "plan", "--json"])
            try:
                j = json.loads(out)
                di = j.get("decision_instances")
                n = len(di) if isinstance(di, (list, dict)) else di
                emit_out("llmctl plan --json: rc=%s decision_instances=%s" % (rc, n))
            except (ValueError, AttributeError):
                emit_out("llmctl plan --json: rc=%s output not JSON (UNKNOWN)" % rc)
    else:
        emit_out("llmctl plan: not probed (pass --probe)")


def show(eff, src, conflicts, as_json, proj, external_edit, contradictions=()):
    if as_json:
        emit_block(json.dumps({"version": 1, "project_root": proj.root, "inherits": proj.inherits(),
                          "project_file": proj.dfile, "user_file": user_file(),
                          "external_edit": external_edit, "contradictions": list(contradictions),
                          "effective": {k: {"value": eff[k], "source": src.get(k, "project")} for k in sorted(eff)},
                          "conflicts": conflicts}, indent=2, sort_keys=True) + "\n")
        return
    emit_out("Decisions for %s (inherits from %s)" % (safe_text(proj.root), proj.inherits()))
    for k in sorted(eff):
        emit_out("  %-40s %-28s [%s]" % (k, yval(eff[k]), src.get(k, "project")))
    for c in conflicts:
        emit_out("  conflict: %s user=%s project=%s (project wins)" % (c["key"], yval(c["user"]), yval(c["project"])))
    for m in contradictions:
        emit_out("  WARNING: %s (reported, not refused; recover with --reset or --unset, or change the other layer)" % m)
    if external_edit:
        emit_out("  WARNING: .constitution/decisions.yml was edited outside the wizard")


def interactive(cur):
    try:
        # errors=surrogateescape: an answer with bytes that are not UTF-8 is read (as lone surrogates) and refused as an
        # invalid answer by _ask_all instead of raising UnicodeDecodeError out of readline (round-6 I-1)
        tty_in = open("/dev/tty", "r", encoding="utf-8", errors="surrogateescape")
        tty_out = open("/dev/tty", "w", encoding="utf-8", errors="backslashreplace")
    except OSError:
        raise Usage("no TTY: run with --non-interactive, --set, --answers or --show")
    try:
        return _ask_all(cur, tty_in, tty_out)
    finally:
        tty_in.close()
        tty_out.close()


def _ask_all(cur, tty_in, tty_out):
    new = dict(cur)
    keys = list(CATALOGUE) + ["agents.%s.wiring" % a for a in AGENTS]
    tty_out.write("Decisions wizard: Enter keeps the shown value, '-' resets to the constitution default.\n")
    for k in keys:
        kind, default, extra = spec_for(k)
        if "locked" in extra:
            continue
        shown = yval(new[k]) if k in new else "%s (inherited)" % yval(default)
        hint = "|".join(extra["choices"]) if "choices" in extra else kind
        for _attempt in range(3):
            tty_out.write("%s [%s] (%s): " % (k, shown, hint))
            tty_out.flush()
            ans = tty_in.readline()
            if ans == "":
                raise Usage("TTY closed")
            ans = ans.strip()
            if any(unicodedata.category(c) == "Cs" for c in ans):
                tty_out.write("  refused: the answer is not valid UTF-8 text\n")
                continue
            if ans == "":
                break
            if ans == "-":
                new.pop(k, None)
                break
            try:
                new[k] = normalize(k, ans)
                break
            except Refused as exc:
                tty_out.write("  refused: %s\n" % redact(exc))
        else:
            raise Refused("too many invalid answers for %s" % k)
    tty_out.write("Write these decisions? [y/N]: ")
    tty_out.flush()
    ok = tty_in.readline().strip().lower() in ("y", "yes")
    return new, ok


class State:
    """Everything read from disk; re-read under the lock before any write (review I8)."""

    def __init__(self, proj, scope, lenient=False):
        """lenient=True (recovery: --reset/--unset/--import only) collects invalid stored entries of the selected
        scope in self.bad instead of refusing, so a constitution or pin change can never brick the wizard."""
        self.ufile = user_file()
        self.user = {}
        self.bad = []
        if os.path.islink(self.ufile) and scope == "user":
            raise Precondition("user decisions file is a symlink; refused")
        if os.path.exists(self.ufile):
            _t, self.user, _i = parse_override_file(self.ufile, "user decisions file",
                                                    self.bad if (lenient and scope == "user") else None)
        if os.path.islink(proj.cdir) or os.path.islink(proj.dfile):
            raise Precondition(".constitution or decisions.yml is a symlink; refused")
        if os.path.exists(proj.cdir) and not os.path.isdir(proj.cdir):
            raise Precondition(".constitution exists and is not a directory; refused")
        self.ptext = read_text(proj.dfile, ".constitution/decisions.yml") if os.path.isfile(proj.dfile) else None
        self.project = {}
        self.pinherits = None
        self.external_edit = False
        if self.ptext is not None:
            _t, self.project, self.pinherits = parse_override_file(
                proj.dfile, ".constitution/decisions.yml", self.bad if (lenient and scope == "project") else None)
            side = (read_text(proj.sfile) or "").strip()
            intent = (read_text(proj.ifile) or "").strip()
            self.external_edit = sha_text(self.ptext) not in (side, intent)
        self.eff, self.src, self.conflicts = effective(self.user, self.project)
        # reported by every read and recovery path, never a refusal (round-4 I-1): only a write that creates a NEW
        # contradiction is refused (apply_changes)
        self.contradictions = check_contradictions(self.eff) or []


def do_check(proj, st, extra_docs):
    warn = 0
    for m in st.contradictions:
        emit_err("check: WARNING: %s (reported, not refused; recover with --reset or --unset, or change the other "
              "layer)" % m)
        warn = 4
    if st.external_edit:
        emit_err("check: .constitution/decisions.yml was edited outside the wizard (sha mismatch)")
        return 4
    if os.path.lexists(proj.ifile):
        emit_err("check: .constitution/decisions.intent is present: an earlier write did not finish (re-run the "
                 "wizard to complete it)")
        return 4
    docs = doc_targets(proj, extra_docs)
    if st.ptext is not None:
        block = render_block(st.pinherits, st.project)
        drift = []
        for name, p in docs:
            t = read_text(p, name) or ""
            if apply_block(t, block, name) != t:
                drift.append(name)
        if drift:
            emit_err("check: managed block out of date or missing in %s (re-run the wizard)" % ",".join(drift))
            return 4
    else:
        orphan = [name for name, p in docs if has_block(read_text(p, name) or "", name)]
        if orphan:
            emit_err("check: managed block present in %s but .constitution/decisions.yml is missing (stale block; "
                  "re-run the wizard or remove the block)" % ",".join(orphan))
            return 4
    if warn:
        emit_err("check: not clean (%d contradiction(s); the override file and the managed blocks themselves match)"
              % len(st.contradictions))
        return warn
    emit_out("check: OK (%d override(s))" % len(st.project))
    return 0


BACKUP_DIR_RE = re.compile(r"(\d{8}T\d{6}Z)-decisions(?:-(\d+))?")


def backup_keep():
    v = os.environ.get("CONSTITUTION_DECISIONS_BACKUP_KEEP", "")
    return int(v) if re.fullmatch(r"[1-9][0-9]{0,3}", v) else 20


def _stamp():
    if os.environ.get("CONSTITUTION_DECISIONS_TEST") == "1":  # test-only clock seam (frozen or backwards clock)
        v = os.environ.get("CONSTITUTION_DECISIONS_TEST_STAMP", "")
        if re.fullmatch(r"\d{8}T\d{6}Z", v):
            return v
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def next_slot(base, rx):
    """(stamp, index) STRICTLY greater than every backup of this wizard already in `base` (round-5 I-1). The old
    lowest-free-name search could reuse a freed low index, producing a name that sorts OLDEST, which prune then
    deleted: the backup just made vanished. Greater-than-all also holds when the clock stands still or goes back."""
    now, best = _stamp(), None
    for e in os.listdir(base):
        m = rx.fullmatch(e)
        if m:
            k = (m.group(1), int(m.group(2) or 1))
            best = k if best is None or k > best else best
    if best is None or now > best[0]:
        return now, 1
    return best[0], best[1] + 1


def slot_name(slot, suffix):
    return "%s-decisions%s%s" % (slot[0], "" if slot[1] == 1 else "-%d" % slot[1], suffix)


def open_base(base):
    """Open a backup location as a directory DESCRIPTOR without following a final symlink (round-6 M-6). Every later
    step (mode change, listing, reservation of the backup name) goes through this descriptor, so a base swapped for a
    symlink after the lstat-style checks can no longer redirect a chmod or a creation into another directory."""
    test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_BASE_DELAY")
    try:
        return os.open(base, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
    except OSError:
        raise Precondition("%s changed while this run was working or is not a plain directory; refused"
                           % safe_text(os.path.basename(base)))


def same_dir(fd, base):
    """The path still names the directory the descriptor holds (not a symlink, same device and inode). Checked before
    each creation and again before the copy. RESIDUAL (documented in the plan): the path-based copy that follows can
    still race a swap that happens between this check and the copy; closing that needs openat for every component of
    the copy and needs a writer with access to the user's own directories."""
    try:
        a, b = os.lstat(base), os.fstat(fd)
    except OSError:
        raise Precondition("%s changed while this run was working; refused" % safe_text(os.path.basename(base)))
    if stat.S_ISLNK(a.st_mode) or (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
        raise Precondition("%s changed while this run was working (it no longer names the directory that was opened); "
                           "nothing more written, re-run to apply" % safe_text(os.path.basename(base)))


def tighten_base(fd, base):
    """A backup location the wizard uses must be private. A pre-existing group/world-accessible one that we own is
    set to 0700 THROUGH THE DESCRIPTOR (reported); one we do not own is reported, not touched."""
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode) or not (st.st_mode & 0o077):
        return
    if st.st_uid == os.getuid():
        os.fchmod(fd, 0o700)
        emit_err("note: backup directory %s was accessible to others (mode %o); set to 0700"
                 % (safe_text(os.path.basename(base)), st.st_mode & 0o777))
    else:
        emit_err("note: backup directory %s is accessible to others and not owned by you; not changed"
                 % safe_text(os.path.basename(base)))


BACKUP_BASES = (".constitution-install-backup", ".decisions-backup")


def prune(base, rx, is_dir):
    """Keep the newest backup_keep() entries THIS wizard created (name pattern); never touches anything else.
    Guard (safe_rm_rf equivalent, §11.4.287): the location must be a REAL (non-symlink) directory named like one of
    the wizard's backup locations, deep enough not to be a system path, and every victim must be a non-symlink
    direct child whose name matches the wizard's pattern and whose resolved parent is that location."""
    if os.path.islink(base) or not os.path.isdir(base) or os.path.basename(base) not in BACKUP_BASES:
        return
    base = os.path.realpath(base)
    if os.path.basename(base) not in BACKUP_BASES or len([x for x in base.split(os.sep) if x]) < 2 \
            or base in home_dirs():
        return
    ours = []
    for e in os.listdir(base):
        m = rx.fullmatch(e)
        fp = os.path.join(base, e)
        if m and not os.path.islink(fp) and (os.path.isdir(fp) if is_dir else os.path.isfile(fp)):
            ours.append(((m.group(1), int(m.group(2) or 1)), fp))
    ours.sort()
    for _k, fp in ours[:max(0, len(ours) - backup_keep())]:
        if os.path.dirname(fp) != base or os.path.islink(fp) or os.path.dirname(os.path.realpath(fp)) != base \
                or not rx.fullmatch(os.path.basename(fp)):  # pragma: no cover - defensive
            continue
        if is_dir:
            shutil.rmtree(fp)
        else:
            os.unlink(fp)


def private_copy(src, out):
    """Backup copy with mode 0600. A decisions-shaped file (anything that is not Markdown) holding key-shaped runs is
    copied REDACTED (round-4 I-4: recovery must not duplicate refused key material into a backup); Markdown docs
    are the user's text and are copied faithfully."""
    if not src.lower().endswith((".md", ".markdown")):
        text = read_text(src, "backup source")
        if text is not None and looks_secret(text):
            text = "# NOTE: key-shaped content was redacted from this backup copy by the wizard (§11.4.10).\n" \
                   + scrub_secrets(text)
            fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
                fh.write(text)
            return
    shutil.copyfile(src, out)
    os.chmod(out, 0o600)


def gitignore_note(proj):
    t = None
    try:
        t = read_text(os.path.join(proj.root, ".gitignore"), ".gitignore")
    except (Refused, Precondition):
        t = None
    if t is None or ".constitution-install-backup" not in t:
        emit_err("note: add .constitution-install-backup/ to .gitignore (backups of project docs and decisions are "
              "kept there, mode 0600/0700)")


def backup(proj, items):
    base = os.path.join(proj.root, ".constitution-install-backup")
    make_dir(base, 0o700)
    bfd = open_base(base)
    try:
        tighten_base(bfd, base)
        test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY")
        slot = next_slot(bfd, BACKUP_DIR_RE)
        while True:  # mkdir (by descriptor) is the exclusive reservation; a lost race moves to the next index
            same_dir(bfd, base)
            name = slot_name(slot, "")
            try:
                os.mkdir(name, 0o700, dir_fd=bfd)
                break
            except FileExistsError:
                slot = (slot[0], slot[1] + 1)
        dest = os.path.join(base, name)
        same_dir(bfd, base)
        for src, rel in items:
            out = os.path.join(dest, rel)
            parent = dest
            for part in os.path.dirname(rel).split(os.sep):
                if part:
                    parent = os.path.join(parent, part)
                    if not os.path.isdir(parent):
                        os.mkdir(parent, 0o700)
            private_copy(src, out)
        same_dir(bfd, base)
        prune(os.path.realpath(base), BACKUP_DIR_RE, True)
    finally:
        os.close(bfd)
    gitignore_note(proj)
    return dest


def check_user_location(proj, ufile):
    """--scope user writes, locks and backups go beside the user file. Refuse when that directory resolves
    inside the project being operated on: user-layer files (and their .decisions-backup/) must never be
    created in a project tree."""
    d = os.path.realpath(os.path.dirname(ufile))
    if proj.contains(d) and not proj.is_home_like():
        raise Precondition("the user decisions file resolves inside the project being operated on; user-scope "
                           "writes, locks and backups go only to a user config directory "
                           "(set CONSTITUTION_DECISIONS_USER_FILE or XDG_CONFIG_HOME outside the project); refused")


def user_backup_tag(ufile):
    """Per-source namespace for user-file backups (round-6 M-3): two user files in one directory (a second
    CONSTITUTION_DECISIONS_USER_FILE) must not share backup names or the keep count of one another."""
    base = os.path.basename(ufile)
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", base)[:32] or "file"
    return "%s_%s" % (safe, hashlib.sha256(os.fsencode(base)).hexdigest()[:8])


def backup_user(ufile, proj):
    """The user file is backed up BESIDE itself (never into a project tree), in a 0700 directory. Names are
    `<UTC>-decisions[-n]@<tag>.yml`, the tag naming the SOURCE file, and pruning counts per tag."""
    check_user_location(proj, ufile)
    base = os.path.join(os.path.dirname(ufile), ".decisions-backup")
    make_dir(base, 0o700)
    tag = user_backup_tag(ufile)
    rx = re.compile(r"(\d{8}T\d{6}Z)-decisions(?:-(\d+))?@%s\.yml" % re.escape(tag))
    bfd = open_base(base)
    try:
        tighten_base(bfd, base)
        test_delay("CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY")
        slot = next_slot(bfd, rx)
        while True:
            same_dir(bfd, base)
            name = slot_name(slot, "@%s.yml" % tag)
            try:
                os.close(os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=bfd))
                break
            except FileExistsError:
                slot = (slot[0], slot[1] + 1)
        dest = os.path.join(base, name)
        same_dir(bfd, base)
        private_copy(ufile, dest)
        same_dir(bfd, base)
        prune(os.path.realpath(base), rx, False)
    finally:
        os.close(bfd)
    return dest


def build_target(a, base, noninter, inter_new):
    """Apply the requested changes to the freshly read override map of the selected scope."""
    target = dict(base)
    if inter_new is not None:  # interactive answers are applied as a diff on top of the re-read state
        old, new = inter_new
        for k in set(old) | set(new):
            if k not in new:
                target.pop(k, None)
            elif old.get(k) != new[k]:
                target[k] = new[k]
    if a.reset:
        target = {}
    if a.imp:
        _t, target, _i = parse_override_file(a.imp, "import file")
    if noninter:
        target.update(env_decisions(a.accept_env))
    if a.answers:
        target.update(parse_answers(a.answers))
    for k in a.unset:
        check_key(k)
        spec_for(k)
        target.pop(k, None)
    target.update(parse_set(a.sets))
    return drop_locked(target)


class Parser(argparse.ArgumentParser):
    def _print_message(self, message, file=None):
        """--help, usage and every other argparse message go through the one emitter (round-6 M-5): argparse would
        write to the raw stream. argparse always passes the stream (stdout for help, stderr for exit messages)."""
        if message and file is not None:
            _emit(file, message, "", block=True)

    def error(self, message):
        # argparse quotes the offending values; show only the option-level problem (round-3 minor), sanitised
        m = re.match(r"(unrecognized arguments|argument [^:]{1,60}: invalid choice)", message)
        raise Usage(redact(m.group(1) + " (value not shown)" if m else message[:300]))


_FAULTS = {
    "ValueError": lambda: ValueError("injected"), "KeyError": lambda: KeyError("injected"),
    "UnicodeDecodeError": lambda: UnicodeDecodeError("utf-8", b"\xff", 0, 1, "injected"),
    "UnicodeEncodeError": lambda: UnicodeEncodeError("utf-8", "x", 0, 1, "injected"),
    "RecursionError": lambda: RecursionError("injected"), "MemoryError": lambda: MemoryError(),
    "OverflowError": lambda: OverflowError("injected"), "BrokenPipeError": lambda: BrokenPipeError(32, "Broken pipe"),
    "RuntimeError": lambda: RuntimeError("injected"), "ZeroDivisionError": lambda: ZeroDivisionError("injected"),
}


def test_fault(var="CONSTITUTION_DECISIONS_TEST_FAULT"):
    """Test-only seam (CONSTITUTION_DECISIONS_TEST=1): raise the named exception before any work (or, with
    CONSTITUTION_DECISIONS_TEST_LATE_FAULT, after a write run has printed its output), so a test can drive the REAL
    process through the catch-all. The set is closed; anything else is ignored."""
    if os.environ.get("CONSTITUTION_DECISIONS_TEST") == "1":
        mk = _FAULTS.get(os.environ.get(var, ""))
        if mk:
            raise mk()


def flush_outcome(rc):
    """THE one final flush (round-8 review B-2), run on EVERY way out of run_cli, so no path leaves buffered stdout
    for the interpreter's exit-time flush (which printed 'Exception ignored while flushing sys.stdout' and exited
    120). emit_flush() points stdout at /dev/null when its flush fails. The flush failure decides the exit code only
    when the run itself succeeded (rc 0): a closed pipe is rc 1 `internal error (BrokenPipeError)`, a full device
    is rc 3 `blocked: ...`; a run that already failed keeps its own code and message (never masked)."""
    try:
        emit_flush()
    except BrokenPipeError as exc:
        return report_internal(type(exc).__name__) if rc == 0 else rc
    except OSError as exc:
        return report_exception(exc) if rc == 0 else rc
    except Exception as exc:  # e.g. ValueError on a closed stream object: same one-line report, never a traceback
        _silence_stdout()
        return report_internal(type(exc).__name__) if rc == 0 else rc
    return rc


def run_cli(argv):
    """The process boundary (round-6 I-1). Engine errors map to their codes; ANY other exception is reported as
    `internal error (<Type>)` with exit 1, never a traceback or an absolute path; Ctrl-C is 130; a closed pipe is
    reported once and stdout is silenced. Every outcome - the error paths and SystemExit (argparse help/version)
    included - ends in flush_outcome() (round-8 review B-2); a SystemExit keeps its own code unless a successful
    exit could not be delivered."""
    try:
        try:
            try:
                test_fault()
                rc = main(argv)
            except (Usage, Precondition, Refused, OSError) as exc:
                if isinstance(exc, BrokenPipeError):
                    raise
                rc = report_exception(exc)
        except KeyboardInterrupt:
            rc = 130
        except BrokenPipeError as exc:
            _silence_stdout()
            rc = report_internal(type(exc).__name__)
        except Exception as exc:  # the catch-all: UnicodeError, RecursionError, MemoryError, OverflowError, ValueError, KeyError...
            rc = report_internal(type(exc).__name__)
    except SystemExit as exc:
        ok = exc.code in (None, 0)
        frc = flush_outcome(0 if ok else 2)
        if ok and frc != 0:
            raise SystemExit(frc)
        raise
    return flush_outcome(rc)


def main(argv):
    ap = Parser(prog="constitution_decisions.sh", allow_abbrev=False,
                                 description="Answer, review and change decision-model choices (local overrides).")
    ap.add_argument("--project-root")
    ap.add_argument("--scope", choices=("project", "user"), default="project")
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--set", action="append", default=[], dest="sets")
    ap.add_argument("--unset", action="append", default=[])
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("--answers")
    ap.add_argument("--import", dest="imp")
    ap.add_argument("--export")
    ap.add_argument("--force-export", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--non-interactive", action="store_true")
    ap.add_argument("--accept-env", action="store_true")
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--doc", action="append", default=[])
    ap.add_argument("--accept-external-edits", action="store_true")
    ap.add_argument("--inherits", help="relative path of the inherited constitution to record (and accept as the "
                                       "project precondition) when it is not at submodules/constitution")
    ap.add_argument("--version", action="store_true")
    a = ap.parse_args(argv)
    if a.version:
        emit_out("constitution_decisions %s" % VERSION)
        return 0
    noninter = a.non_interactive or os.environ.get("CONSTITUTION_DECISIONS_NON_INTERACTIVE") == "1" \
        or os.environ.get("JEV_BOOTSTRAP_NON_INTERACTIVE") == "1"
    mutating = bool(a.sets or a.unset or a.reset or a.answers or a.imp)
    readonly = a.show or a.check or a.export is not None or a.plan
    if mutating and readonly:
        raise Usage("read-only actions (--show/--check/--export/--plan) cannot be combined with changes")
    if a.force_export and a.export is None:
        raise Usage("--force-export needs --export")
    if len(set(a.unset)) != len(a.unset) or set(a.unset) & {s.split("=", 1)[0] for s in a.sets}:
        raise Usage("a decision key is given twice")
    if a.inherits is not None and (not INHERITS_RE.fullmatch(a.inherits) or ".." in a.inherits.split("/")
                                   or looks_secret(a.inherits)):
        raise Usage("--inherits must be a relative constitution path")
    proj = Project(a.project_root or os.getcwd())
    if a.inherits is not None:
        if not proj.inherits_dir_ok(a.inherits):
            raise Usage("--inherits must name an existing directory inside the project")
        proj.inh_override = a.inherits
    else:
        rec = proj.recorded_inherits()
        if rec:
            proj.inh_override, proj.inh_recorded = rec, True
    user_only = a.scope == "user" and not readonly  # a user-layer write needs no project repository
    if (not readonly or a.export not in (None, "-")) and not user_only:
        proj.require_inherited(a.inherits)

    if readonly:
        st = State(proj, a.scope)
        if a.show:
            show(st.eff, st.src, st.conflicts, a.json, proj, st.external_edit, st.contradictions)
            return 0
        if a.check:
            return do_check(proj, st, a.doc)
        if a.export is not None:
            return do_export(proj, st, a)
        for m in st.contradictions:
            emit_err("plan: WARNING: %s (reported, not refused)" % m)
        do_plan(st.eff, proj.inherits(), a.probe)
        return 0

    inter_new = None
    if not mutating and not noninter:
        pre = State(proj, a.scope)
        base = dict(pre.project if a.scope == "project" else pre.user)
        new, ok = interactive(base)
        if not ok:
            emit_out("no changes written (not confirmed)")
            return 0
        inter_new = (base, new)

    recovery = bool(a.reset or a.unset or a.imp)
    if a.scope == "user":
        check_user_location(proj, user_file())
    if a.dry_run:
        st = State(proj, a.scope, lenient=recovery)
        return apply_changes(proj, st, a, noninter, inter_new, dry=True)
    lockdir = proj.cdir if a.scope == "project" else os.path.dirname(user_file())
    if a.scope == "project":
        make_dir(proj.cdir)
    else:
        make_dir(lockdir, 0o700)
    test_delay("CONSTITUTION_DECISIONS_TEST_PRELOCK_DELAY")
    fd = acquire_lock(lockdir)
    if fd is None:
        emit_err("another decisions run holds the lock")
        return 5
    try:
        st = State(proj, a.scope, lenient=recovery)  # re-read under the lock
        return apply_changes(proj, st, a, noninter, inter_new, dry=False)
    finally:
        os.close(fd)


def do_export(proj, st, a):
    text = dump_file(st.pinherits or proj.inherits(), st.project if a.scope == "project" else st.user)
    if a.export == "-":
        emit_block(text)
        return 0
    p = proj.user_target(a.export, "--export")
    rel = proj.rel(p)
    if not os.path.isdir(os.path.dirname(p)):
        raise Precondition("--export %s: the directory does not exist" % rel)
    if os.path.isdir(p):
        raise Precondition("--export %s is a directory; refused" % rel)
    if os.path.exists(p) and not a.force_export:
        raise Precondition("%s exists; pass --force-export to replace it (a backup is taken)" % rel)
    if a.dry_run:  # review I-1: dry-run writes nothing in every mode (no file, no lock, no backup, no dir)
        emit_out("dry-run: nothing written; would export to %s%s" % (rel, " (after a backup)" if os.path.exists(p)
                                                                    else ""))
        return 0
    old = read_text(p, "--export target")
    relf = proj.rel
    preflight([(p, text)] + ([(os.path.join(proj.root, ".decisions-preflight"), old)] if old is not None else []),
              relf)
    try:
        make_dir(proj.cdir)
        fd = acquire_lock(proj.cdir)
        if fd is None:
            emit_err("another decisions run holds the lock")
            return 5
        try:
            if old is not None:
                dest = backup(proj, [(p, rel)])
                emit_out("backup: %s" % proj.rel_own(dest))
            atomic_write(p, text, expect=old, guard=proj.guard("--export", True))
        finally:
            os.close(fd)
    except OSError as exc:
        raise Precondition("--export %s failed (%s)" % (rel, exc.strerror or type(exc).__name__))
    emit_out("exported: %s" % proj.rel(p))
    return 0


def apply_changes(proj, st, a, noninter, inter_new, dry):
    if st.bad:  # recovery mode: only removing/replacing the invalid stored entries is allowed
        if not (a.reset or a.imp) and not all(k in a.unset for k, _m in st.bad):
            raise Refused(redact(st.bad[0][1]))
        for _k, msg in st.bad:
            emit_err("note: dropping an invalid stored decision (%s)" % redact(msg))
    if a.scope == "project" and st.external_edit and not a.accept_external_edits:
        raise Refused(".constitution/decisions.yml was edited outside the wizard; review it, then re-run "
                      "with --accept-external-edits")
    base = st.project if a.scope == "project" else st.user
    target = build_target(a, base, noninter, inter_new)
    new_user, new_proj = (st.user, target) if a.scope == "project" else (target, st.project)
    eff2, _s, _c = effective(new_user, new_proj)
    created = [m for m in (check_contradictions(eff2) or []) if m not in st.contradictions]
    if created:  # only a NEW contradiction refuses a write; an existing one never blocks recovery (round-4 I-1)
        raise Refused(created[0])
    if a.scope == "user":
        return write_user(st.ufile, proj.inherits(), target, dry, proj)
    return write_project(proj, proj.inherits(), target, a, eff2, dry)


def write_user(ufile, inherits, target, dry, proj):
    text = dump_file(inherits, target)
    check_user_location(proj, ufile)
    if os.path.islink(ufile):
        raise Precondition("user decisions file is a symlink; refused")
    if read_text(ufile, "user decisions file") == text:
        emit_out("no-change: user decisions already up to date")
        return 0
    if dry:
        emit_out("dry-run: would write the user decisions file")
        emit_block(text)
        return 0
    old = read_text(ufile, "user decisions file")
    ubase = os.path.join(os.path.dirname(ufile), ".decisions-backup")
    preflight([(ufile, text)] + ([(os.path.join(ubase if os.path.isdir(ubase) else os.path.dirname(ufile),
                                                ".decisions-preflight"), old)] if old is not None else []),
              lambda x: "user decisions " + ("directory" if os.path.isdir(x) else "file"))
    try:
        if old is not None:
            emit_out("backup (user decisions file): %s" % safe_text(backup_user(ufile, proj)))
        clean_stale_temps([(os.path.dirname(ufile), os.path.basename(ufile))])
        atomic_write(ufile, text, expect=old, base_mode=0o600)
    except OSError as exc:
        raise Precondition("writing the user decisions file failed (%s); the file is unchanged"
                           % (exc.strerror or type(exc).__name__))
    emit_out("written: user decisions file")
    return 0


def write_project(proj, inherits, target, a, eff, dry):
    new_text = dump_file(inherits, target)
    new_sha = sha_text(new_text)
    block = render_block(inherits, target)
    docs = doc_targets(proj, a.doc)
    changes = []  # (path, rel, new text, the content the plan was computed from: None = absent)
    old_yml = read_text(proj.dfile, ".constitution/decisions.yml")
    if old_yml != new_text:
        changes.append((proj.dfile, ".constitution/decisions.yml", new_text, old_yml))
    for name, p in docs:
        raw = read_text(p, name)
        old = raw or ""
        new = apply_block(old, block, name)
        if new != old:
            changes.append((p, name, new, raw))
    side_ok = (read_text(proj.sfile) or "").strip() == new_sha
    if not changes and side_ok and not os.path.exists(proj.ifile):
        emit_out("no-change: decisions already up to date")
        return 0
    if dry:
        emit_out("dry-run: nothing written. Planned changes:")
        for _p, rel, _t, _o in changes:
            emit_out("  would update %s" % rel)
        if not side_ok:
            emit_out("  would update .constitution/decisions.sha256")
        print_bootstrap(eff, inherits, "printed, NOT run")
        return 0
    clean_stale_temps([(proj.cdir, "decisions.yml"), (proj.cdir, "decisions.sha256"),
                       (proj.cdir, "decisions.intent")] + [(os.path.dirname(p), os.path.basename(p))
                                                           for _n, p in docs])
    to_backup = [(p, rel) for p, rel, _t, _o in changes if os.path.exists(p)]
    rel = proj.rel
    bdir = os.path.join(proj.root, ".constitution-install-backup")
    preflight([(p, t) for p, _r, t, _o in changes] + [(proj.ifile, new_sha + "\n"), (proj.sfile, new_sha + "\n")]
              + ([(os.path.join(bdir if os.path.isdir(bdir) else proj.root, ".decisions-preflight"),
                   "".join(o or "" for _p, _r, _t, o in changes))] if to_backup else []), rel)
    step = "backup"
    try:
        if to_backup:
            dest = backup(proj, to_backup)
            emit_out("backup: %s" % proj.rel_own(dest))
        step = ".constitution/decisions.intent"
        atomic_write(proj.ifile, new_sha + "\n", expect=False, guard=proj.guard(".constitution", False))
        for p, r_, text, old in changes:
            step = r_
            atomic_write(p, text, expect=old, guard=proj.guard(r_, p != proj.dfile))
            emit_out("written: %s" % r_)
        step = ".constitution/decisions.sha256"
        atomic_write(proj.sfile, new_sha + "\n", expect=False, guard=proj.guard(".constitution", False))
        os.unlink(proj.ifile)
    except OSError as exc:
        raise Precondition("writing %s failed (%s); %s" % (step, exc.strerror or type(exc).__name__,
                           "nothing was changed" if step == "backup" else unfinished_note(step, to_backup)))
    except Refused as exc:
        if step == "backup":
            raise
        raise Refused("%s; %s" % (exc, unfinished_note(step, to_backup)))
    print_bootstrap(eff, inherits, "printed, NOT run")
    test_fault("CONSTITUTION_DECISIONS_TEST_LATE_FAULT")
    return 0


def unfinished_note(step, backed_up):
    """What a failed write left behind, stated truthfully (round-8 review MINOR-2): when the decisions.intent marker
    itself could not be written, nothing was recorded and no project file was touched by this run."""
    if step == ".constitution/decisions.intent":
        return ("this run changed no project file and recorded no .constitution/decisions.intent"
                + ("; the backup this run took is kept" if backed_up else ""))
    return ".constitution/decisions.intent records the unfinished change and the next successful run completes it"


if __name__ == "__main__":
    install_excepthook()
    sys.exit(run_cli(sys.argv[1:]))
