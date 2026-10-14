#!/usr/bin/env python3
"""agent_label_frontmatter_check.py - strict, generator-INDEPENDENT validator for
agent-type label definitions (constitution 11.4.182 / 11.4.231(F)).

Purpose : decide whether each given .md file is a well-formed label agent
          definition: name == T<N>-<branch>-<alias>-<model>-<effort> (== file
          name, <= 120 chars), model in {sonnet,opus}, effort in
          {low,medium,high,xhigh,max}, color in the supported set, description
          starting with the full 11.4.182 label "(T<N>/<branch> - <alias> -
          <model> - <effort>)" consistent with the name (a '?' or placeholder
          alias is rejected), closed key set, no duplicate keys. When PyYAML is
          importable the frontmatter is parsed a second time with
          yaml.safe_load and the two parses must agree; each OK line says
          whether that cross-parse ran or was skipped.
Usage   : python3 -I agent_label_frontmatter_check.py FILE [FILE...]
Inputs  : agent definition files.
Outputs : one "OK file (cross-parse: ran|skipped)" or "BAD file: reason" line
          per file; exit 0 iff all OK,
          1 if any BAD, 2 on usage error.
Side-effects: none (read-only).
Deps    : python3 (PyYAML optional - used only as a cross-check).
Cross-refs: gen_agent_label_defs.sh, test_gen_agent_label_defs.sh, 11.4.201.
"""
import os
import re
import sys

MODELS = ("sonnet", "opus")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
COLORS = ("red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan")
KEYS = ("name", "description", "model", "effort", "color")
NAME_MAX = 120
NAME_RE = re.compile(r"^T([0-9]+)-[a-z0-9]+(-[a-z0-9]+)+-(sonnet|opus)-(low|medium|high|xhigh|max)$")
DESC_RE = re.compile(r'^"\(T([0-9]+)/([A-Za-z0-9._/-]+) - ([A-Za-z0-9._/-]+) - (sonnet|opus) - (low|medium|high|xhigh|max)\) [^"\\]*"$')
CROSS = {"ran": 0}


def sanitise(text):
    """Byte-wise, locale-free twin of agent_label_lib.sh al_sanitise."""
    out = []
    for b in text.encode("utf-8"):
        if 65 <= b <= 90:
            b += 32
        out.append(chr(b) if (97 <= b <= 122 or 48 <= b <= 57) else "-")
    s = re.sub(r"-+", "-", "".join(out))
    return s.strip("-")


def check(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except (OSError, UnicodeDecodeError) as exc:
        return "unreadable: %s" % exc
    if not lines or lines[0] != "---":
        return "no frontmatter (first line is not ---)"
    try:
        end = lines.index("---", 1)
    except ValueError:
        return "frontmatter not closed"
    fm = lines[1:end]
    kv = {}
    for ln in fm:
        m = re.match(r"^([A-Za-z][A-Za-z0-9_]*): (.*)$", ln)
        if not m:
            return "malformed frontmatter line: %r" % ln
        k, v = m.group(1), m.group(2)
        if k not in KEYS:
            return "unknown key %r" % k
        if k in kv:
            return "duplicate key %r" % k
        kv[k] = v
    for k in KEYS:
        if k not in kv:
            return "missing key %r" % k
    try:
        import yaml  # optional cross-check
        parsed = yaml.safe_load("\n".join(fm))
        for k in KEYS:
            if str(parsed.get(k)).strip() != kv[k].strip().strip('"'):
                return "yaml cross-parse disagrees on %r" % k
        CROSS["ran"] = 1
    except ImportError:
        CROSS["ran"] = 0
    except Exception as exc:  # yaml present but frontmatter not valid YAML
        return "yaml parse error: %s" % exc
    name = kv["name"]
    if len(name) > NAME_MAX or ":" in name or "/" in name:
        return "name violates length/charset rules"
    m = NAME_RE.match(name)
    if not m:
        return "name %r does not match T<N>-<branch>-<alias>-<model>-<effort>" % name
    n, mo, ef = m.group(1), m.group(3), m.group(4)
    if name + ".md" != os.path.basename(path):
        return "name %r != file name %r" % (name, os.path.basename(path))
    if kv["model"] not in MODELS or kv["model"] != mo:
        return "model %r not in %s or != name segment %r" % (kv["model"], MODELS, mo)
    if kv["effort"] not in EFFORTS or kv["effort"] != ef:
        return "effort %r not in ladder or != name segment %r" % (kv["effort"], ef)
    if kv["color"] not in COLORS:
        return "color %r not in supported set" % kv["color"]
    d = DESC_RE.match(kv["description"])
    if not d:
        return "description does not begin with the 11.4.182 label text"
    dn, dbr, dal, dmo, def_ = d.groups()
    if (dn, dmo, def_) != (n, mo, ef):
        return "description label track/model/effort disagree with name"
    want = "T%s-%s-%s-%s-%s" % (dn, sanitise(dbr), sanitise(dal), dmo, def_)
    if not sanitise(dal):
        return "description alias %r is empty after sanitising" % dal
    if want != name:
        return "name %r != %r built from the description label" % (name, want)
    return None


def main(argv):
    if not argv:
        sys.stderr.write("usage: agent_label_frontmatter_check.py FILE...\n")
        return 2
    rc = 0
    for p in argv:
        r = check(p)
        if r is None:
            print("OK %s (cross-parse: %s)" % (p, "ran" if CROSS["ran"] else "skipped"))
        else:
            print("BAD %s: %s" % (p, r))
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
