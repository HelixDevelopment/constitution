r"""ext_yaml.py — strict parser and deterministic emitter for a RESTRICTED YAML subset.

Part of the constitution extension engine (scripts/constitution_ext/). Exists because PyYAML / yq
may be absent on a consumer host and because a full YAML loader is a larger attack surface than an
extension manifest needs. Standard library only.

Accepted subset
  * block mappings `key: value` with plain keys matching [A-Za-z0-9_][A-Za-z0-9_.-]*
  * block sequences `- item` (a sequence may sit at its parent key's indent), `- key: v` items
  * scalars: plain, 'single quoted' ('' escape), "double quoted" (\\ \" \n \t \r \/ only)
  * plain true/false -> bool, null/~ -> None, -?(0|[1-9][0-9]{0,17}) -> int, everything else -> str
  * a plain scalar that YAML 1.1 (PyYAML) would read as something else is REJECTED, so this parser and
    PyYAML never disagree silently: octal/hex/binary/underscore/sexagesimal numbers (010, 0x10, 1_000),
    floats (1.0, .inf, .nan), yes/no/on/off/y/n and their case variants, True/NULL variants,
    timestamps (2026-10-29), '=' and '<<', and leading-sign ints (+5). Quote such values.
  * flow forms: [] {} and a one-line flat list of scalars [a, "b", 3]
  * comments: full-line `#`, or ` #` after a value outside quotes
Rejected (YamlError): tabs in indentation, anchors &, aliases *, tags !, block scalars | >,
document markers --- / ..., non-empty flow mappings, nested flow, directives, duplicate keys,
NUL and other C0/C1 control characters (except tab, LF, CR), U+2028/U+2029 (line breaks to YAML
1.1 but not to this parser), a byte-order mark anywhere, integers longer than 18 digits, keys that
YAML 1.1 would read as a non-string (on:, 010:), bad indentation, `key: a: b` ambiguity, a top-level
scalar or list. The emitter double-quotes every string and refuses one it could not read back.
Limits: MAX_BYTES 262144, MAX_LINES 10000, MAX_DEPTH 20, MAX_SCALAR 8192, MAX_NODES 50000.

API: parse(text) -> dict ; dump(value) -> str (round-trips through parse, byte-stable).
"""
import re

MAX_BYTES = 262144
MAX_LINES = 10000
MAX_DEPTH = 20
MAX_SCALAR = 8192
MAX_NODES = 50000

KEY_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\Z")
INT_RE = re.compile(r"-?(0|[1-9][0-9]*)\Z")
MAX_INT_DIGITS = 18
# Plain scalars that YAML 1.1 (PyYAML's implicit resolvers) would type as int/float/bool/null/timestamp/
# merge/value. Our own accepted forms (true, false, null, ~, -?(0|[1-9][0-9]*)) are resolved before
# this is consulted, so anything matching here is a disagreement and is refused.
YAML11_RE = re.compile(r"""(?x)(?:
    [-+]?0b[0-1_]+ | [-+]?0[0-7_]+ | [-+]?(?:0|[1-9][0-9_]*) | [-+]?0x[0-9a-fA-F_]+
  | [-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+
  | [-+]?(?:[0-9][0-9_]*)\.[0-9_]*(?:[eE][-+]?[0-9]+)? | [-+]?\.[0-9_]+(?:[eE][-+]?[0-9]+)?
  | [-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*
  | [-+]?\.(?:inf|Inf|INF) | \.(?:nan|NaN|NAN)
  | y|Y|n|N|yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF
  | null|Null|NULL|~
  | [0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:(?:[Tt]|[ ]+)[0-9]{1,2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]*)?(?:[ ]*(?:Z|[-+][0-9]{1,2}(?::[0-9]{2})?))?)?
  | = | <<
)""")
_BAD_TEXT_RE = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u2028\u2029\ufeff\ud800-\udfff]")


class YamlError(ValueError):
    pass


class _P:
    def __init__(self, text, max_bytes, max_lines, max_nodes):
        self.max_nodes = max_nodes
        if "\x00" in text:
            raise YamlError("NUL byte in document")
        bad = _BAD_TEXT_RE.search(text)
        if bad:
            raise YamlError("control or line-separator character U+%04X is not allowed" % ord(bad.group(0)))
        if re.search(r"\r(?!\n)", text):  # RULE:Y-lone-cr (PyYAML reads a lone CR as a line break; this parser would not)
            raise YamlError("a carriage return that is not followed by a line feed is not allowed")
        if len(text.encode("utf-8", "surrogatepass")) > max_bytes:
            raise YamlError("document too large (> %d bytes)" % max_bytes)
        raw = text.split("\n")
        if len(raw) > max_lines:
            raise YamlError("document has too many lines (> %d)" % max_lines)
        self.lines = []  # (indent, content, lineno)
        for n, line in enumerate(raw, 1):
            line = line.rstrip("\r")
            stripped = line.lstrip(" ")
            lead = line[: len(line) - len(line.lstrip(" \t"))]
            if "\t" in lead:
                raise YamlError("line %d: tab in indentation" % n)
            content = _strip_comment(stripped, n)
            if content == "":
                continue
            if content in ("---", "...") or content.startswith("--- ") or content.startswith("%"):
                raise YamlError("line %d: document markers and directives are not supported" % n)
            self.lines.append((len(line) - len(stripped), content, n))
        self.i = 0
        self.nodes = 0

    def node(self):
        self.nodes += 1
        if self.nodes > self.max_nodes:
            raise YamlError("too many nodes (> %d)" % self.max_nodes)

    def peek(self):
        return self.lines[self.i] if self.i < len(self.lines) else None

    def block(self, indent, depth):
        if depth > MAX_DEPTH:
            raise YamlError("nesting depth exceeds %d" % MAX_DEPTH)
        ln = self.peek()
        if ln[1] == "-" or ln[1].startswith("- "):
            return self.seq(indent, depth)
        return self.mapping(indent, depth)

    def mapping(self, indent, depth):
        out = {}
        while True:
            ln = self.peek()
            if ln is None or ln[0] < indent:
                return out
            ind, content, n = ln
            if ind > indent:
                raise YamlError("line %d: unexpected indentation" % n)
            if content == "-" or content.startswith("- "):
                return out if out else self._bad(n, "sequence item where a mapping key was expected")
            key, rest = _split_key(content, n)
            if key in out:
                raise YamlError("line %d: duplicate key %r" % (n, key))
            self.node()
            self.i += 1
            if rest == "":
                nxt = self.peek()
                if nxt is not None and nxt[0] > indent:
                    out[key] = self.block(nxt[0], depth + 1)
                elif nxt is not None and nxt[0] == indent and (nxt[1] == "-" or nxt[1].startswith("- ")):
                    out[key] = self.seq(indent, depth + 1)
                else:
                    out[key] = None
            else:
                out[key] = _scalar(rest, n, allow_flow=True)
                nxt = self.peek()
                if nxt is not None and nxt[0] > indent:
                    raise YamlError("line %d: unexpected indentation" % nxt[2])

    def seq(self, indent, depth):
        out = []
        while True:
            ln = self.peek()
            if ln is None or ln[0] < indent:
                return out
            ind, content, n = ln
            if ind > indent:
                raise YamlError("line %d: unexpected indentation" % n)
            if not (content == "-" or content.startswith("- ")):
                return out
            self.node()
            if len(out) >= self.max_nodes:
                raise YamlError("line %d: sequence too long" % n)
            rest = content[1:]
            item = rest.lstrip(" ")
            if item == "":
                self.i += 1
                nxt = self.peek()
                if nxt is not None and nxt[0] > indent:
                    out.append(self.block(nxt[0], depth + 1))
                else:
                    out.append(None)
                continue
            item_indent = indent + 1 + (len(rest) - len(item))
            if _looks_like_key(item):
                self.lines[self.i] = (item_indent, item, n)
                out.append(self.mapping(item_indent, depth + 1))
            elif item == "-" or item.startswith("- "):
                raise YamlError("line %d: compact nested sequences are not supported" % n)
            else:
                self.i += 1
                out.append(_scalar(item, n, allow_flow=True))
                nxt = self.peek()
                if nxt is not None and nxt[0] > indent:
                    raise YamlError("line %d: unexpected indentation" % nxt[2])

    @staticmethod
    def _bad(n, msg):
        raise YamlError("line %d: %s" % (n, msg))


def _strip_comment(s, n):
    if s.startswith("#"):
        return ""
    q = None
    i = 0
    while i < len(s):
        c = s[i]
        if q == '"':
            if c == "\\":
                i += 2
                continue
            if c == '"':
                q = None
        elif q == "'":
            if c == "'":
                if i + 1 < len(s) and s[i + 1] == "'":
                    i += 2
                    continue
                q = None
        else:
            if c in "\"'" and (i == 0 or s[i - 1] in " :[,-"):
                q = c
            elif c == "#" and i > 0 and s[i - 1] == " ":
                return s[:i].rstrip(" ")
        i += 1
    return s.rstrip(" ")


def _looks_like_key(s):
    m = re.match(r"([A-Za-z0-9_][A-Za-z0-9_.-]*):( |\Z)", s)
    return m is not None


def _split_key(content, n):
    m = re.match(r"([^:]*):( (.*)|\Z)", content)
    if not m:
        raise YamlError("line %d: expected 'key: value'" % n)
    key = m.group(1)
    if not KEY_RE.match(key):
        raise YamlError("line %d: invalid key %r (plain [A-Za-z0-9_.-] keys only)" % (n, key))
    if YAML11_RE.fullmatch(key):
        raise YamlError("line %d: key %r would not be a string in YAML 1.1 (rename it)" % (n, key))
    rest = (m.group(3) or "").strip(" ")
    return key, rest


def _scalar(s, n, allow_flow=False):
    if len(s) > MAX_SCALAR:
        raise YamlError("line %d: scalar longer than %d characters" % (n, MAX_SCALAR))
    c = s[0]
    if c == '"':
        v, end = _dq(s, n)
        if s[end:].strip(" "):
            raise YamlError("line %d: text after closing quote" % n)
        return v
    if c == "'":
        v, end = _sq(s, n)
        if s[end:].strip(" "):
            raise YamlError("line %d: text after closing quote" % n)
        return v
    if c == "[":
        if not allow_flow:
            raise YamlError("line %d: nested flow collections are not supported" % n)
        return _flow_seq(s, n)
    if c == "{":
        if s.replace(" ", "") == "{}":
            return {}
        raise YamlError("line %d: flow mappings are not supported" % n)
    if c in "&*!|>%@`]}":
        raise YamlError("line %d: unsupported YAML construct %r" % (n, c))
    if ": " in s or s.endswith(":"):
        raise YamlError("line %d: ambiguous ':' in plain scalar (quote it)" % n)
    if s in ("true", "false"):
        return s == "true"
    if s in ("null", "~"):
        return None
    if INT_RE.match(s):
        if len(s.lstrip("-")) > MAX_INT_DIGITS:
            raise YamlError("line %d: integer longer than %d digits" % (n, MAX_INT_DIGITS))
        return int(s)
    if YAML11_RE.fullmatch(s):
        raise YamlError("line %d: ambiguous plain scalar (YAML 1.1 would not read it as a string; quote it)" % n)
    return s


DQ_ESC = {"\\": "\\", '"': '"', "n": "\n", "t": "\t", "r": "\r", "/": "/"}


def _dq(s, n):
    out = []
    i = 1
    while i < len(s):
        c = s[i]
        if c == "\\":
            if i + 1 >= len(s) or s[i + 1] not in DQ_ESC:
                raise YamlError("line %d: unsupported escape in double-quoted string" % n)
            out.append(DQ_ESC[s[i + 1]])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise YamlError("line %d: unterminated double-quoted string" % n)


def _sq(s, n):
    out = []
    i = 1
    while i < len(s):
        c = s[i]
        if c == "'":
            if i + 1 < len(s) and s[i + 1] == "'":
                out.append("'")
                i += 2
                continue
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise YamlError("line %d: unterminated single-quoted string" % n)


def _flow_seq(s, n):
    if not s.endswith("]"):
        raise YamlError("line %d: unterminated flow sequence" % n)
    body = s[1:-1].strip(" ")
    if body == "":
        return []
    items = []
    cur = []
    q = None
    i = 0
    while i < len(body):
        c = body[i]
        if q:
            cur.append(c)
            if q == '"' and c == "\\" and i + 1 < len(body):
                cur.append(body[i + 1])
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
            cur.append(c)
        elif c == ",":
            items.append("".join(cur).strip(" "))
            cur = []
        elif c in "[]{}":
            raise YamlError("line %d: nested flow collections are not supported" % n)
        else:
            cur.append(c)
        i += 1
    if q:
        raise YamlError("line %d: unterminated quote in flow sequence" % n)
    items.append("".join(cur).strip(" "))
    if any(x == "" for x in items):
        raise YamlError("line %d: empty item in flow sequence" % n)
    return [_scalar(x, n, allow_flow=False) for x in items]


def parse(text, max_bytes=MAX_BYTES, max_lines=MAX_LINES, max_nodes=MAX_NODES):
    """Parse TEXT (str) into a dict. Raises YamlError on anything outside the subset.
    The size limits default to the manifest limits; the engine raises them for its own state files."""
    if not isinstance(text, str):
        raise YamlError("document must be text")
    if text.startswith("\ufeff"):
        raise YamlError("byte-order mark is not supported")
    p = _P(text, max_bytes, max_lines, max_nodes)
    if not p.lines:
        return {}
    first = p.lines[0]
    if len(p.lines) == 1 and first[1].replace(" ", "") == "{}":
        return {}
    if first[0] != 0:
        raise YamlError("line %d: document must start at column 0" % first[2])
    if first[1] == "-" or first[1].startswith("- ") or not _looks_like_key(first[1]):
        raise YamlError("line %d: top level must be a mapping" % first[2])
    v = p.mapping(0, 1)
    if p.peek() is not None:
        raise YamlError("line %d: unexpected content" % p.peek()[2])
    return v


# ── emitter ────────────────────────────────────────────────────────────────────────────────
def _q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r") + '"'


def _sc(v):
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        if len(str(abs(v))) > MAX_INT_DIGITS:
            raise YamlError("cannot dump an integer longer than %d digits" % MAX_INT_DIGITS)
        return str(v)
    if isinstance(v, str):
        if _BAD_TEXT_RE.search(v) or "\x00" in v:
            raise YamlError("cannot dump a string with control or line-separator characters")
        return _q(v)
    raise YamlError("cannot dump %r" % type(v).__name__)


def _dump(v, ind, out):
    pad = "  " * ind
    if isinstance(v, dict):
        for k in sorted(v):
            if not KEY_RE.match(k) or YAML11_RE.fullmatch(k):
                raise YamlError("cannot dump key %r" % k)
            x = v[k]
            if isinstance(x, dict) and x:
                out.append("%s%s:" % (pad, k))
                _dump(x, ind + 1, out)
            elif isinstance(x, list) and x:
                out.append("%s%s:" % (pad, k))
                _dump(x, ind + 1, out)
            elif isinstance(x, dict):
                out.append("%s%s: {}" % (pad, k))
            elif isinstance(x, list):
                out.append("%s%s: []" % (pad, k))
            else:
                out.append("%s%s: %s" % (pad, k, _sc(x)))
    elif isinstance(v, list):
        for x in v:
            if isinstance(x, dict) and x:
                sub = []
                _dump(x, ind + 1, sub)
                sub[0] = pad + "- " + sub[0].lstrip(" ")
                out.extend(sub)
            elif isinstance(x, list) and x:
                raise YamlError("nested sequences are not supported by the emitter")
            elif isinstance(x, dict):
                out.append(pad + "- {}")
            elif isinstance(x, list):
                out.append(pad + "- []")
            else:
                out.append(pad + "- " + _sc(x))
    else:
        raise YamlError("top level must be a mapping")


def dump(value):
    """Deterministic emitter (sorted keys, quoted strings). Inverse of parse() for its outputs."""
    if not isinstance(value, dict):
        raise YamlError("top level must be a mapping")
    out = []
    _dump(value, 0, out)
    return "\n".join(out) + "\n" if out else "{}\n"
