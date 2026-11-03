#!/usr/bin/env python3
"""helix_deps_field.py - read named fields of ONE named dep from helix-deps.yaml, structurally (constitution 11.4.31).

Purpose
    Replaces hand-written awk/grep readers of a dep entry (bare `-`, quoted keys, `key :`, duplicate keys
    all fooled them). Parses with the 11.4.31 verifier's StrictLoader (all scalars strings, duplicate keys
    refused), like helix_deps_tsv.py, but can return fields that reader does not emit (e.g. recursive_init).
Usage
    python3 -I helix_deps_field.py <manifest> <dep-name> <field> [<field> ...]
Output (stdout): the requested field values, US (0x1f) separated, in request order; an absent field is "".
Exit codes
    0 ok | 9 no dep with that name (parsed fine; nothing printed) | 3 PyYAML unavailable
    (or HELIX_DEPS_FIELD_FORCE_NO_YAML=1, a test switch honoured ONLY together with HELIX_TEST_MODE=1; alone it is ignored) | 4 unreadable / unparseable / duplicate key
    6 unknown shape (top level not a mapping, deps not a list, a dep not a mapping, two deps with the same
    name = ambiguous, a requested value that is not a string or contains any C0 control character (0x00-0x1f, incl. US, LF, CR, NUL) or DEL (0x7f)) | 7 usage.
    On any non-zero exit nothing is printed to stdout. Read-only; no network.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
US = "\x1f"
MAXB = 1048576


def _bad_value(v):
    """True iff v has any C0 control char (incl. NUL, US, LF, CR) or DEL."""
    return any(ord(c) < 0x20 or ord(c) == 0x7f for c in v)


def main(argv):
    if len(argv) < 4:
        print("usage: helix_deps_field.py <manifest> <dep-name> <field>...", file=sys.stderr)
        return 7
    if os.environ.get("HELIX_DEPS_FIELD_FORCE_NO_YAML") == "1" and os.environ.get("HELIX_TEST_MODE") == "1":
        print("helix_deps_field: PyYAML unavailable (forced by test switch)", file=sys.stderr)
        return 3
    try:
        import helix_deps_manifest as hm
    except Exception as exc:
        print("helix_deps_field: cannot import parser: %s" % exc, file=sys.stderr)
        return 3
    if hm.yaml is None:
        print("helix_deps_field: PyYAML unavailable", file=sys.stderr)
        return 3
    try:
        with open(argv[1], "rb") as fh:
            raw = fh.read(MAXB + 1)
        if len(raw) > MAXB:
            print("helix_deps_field: manifest larger than 1 MiB", file=sys.stderr)
            return 4
        text = raw.decode("utf-8")
    except Exception as exc:
        print("helix_deps_field: unreadable: %s" % exc, file=sys.stderr)
        return 4
    doc, err = hm.load_manifest_text(text)
    if err:
        print("helix_deps_field: %s" % err, file=sys.stderr)
        return 4
    if not isinstance(doc, dict):
        print("helix_deps_field: top level is not a mapping", file=sys.stderr)
        return 6
    deps = doc.get("deps", "")
    if deps in ("", None):
        deps = []
    if not isinstance(deps, list):
        print("helix_deps_field: deps is not a list", file=sys.stderr)
        return 6
    hits = []
    for i, d in enumerate(deps):
        if not isinstance(d, dict):
            print("helix_deps_field: deps[%d] is not a mapping" % i, file=sys.stderr)
            return 6
        n = d.get("name", "")
        if isinstance(n, str) and n.strip() == argv[2]:
            hits.append(d)
    if not hits:
        return 9
    if len(hits) > 1:
        print("helix_deps_field: %d deps named %r (ambiguous)" % (len(hits), argv[2]), file=sys.stderr)
        return 6
    vals = []
    for f in argv[3:]:
        v = hits[0].get(f, "")
        if not isinstance(v, str) or _bad_value(v):
            print("helix_deps_field: %s.%s has an unusable value" % (argv[2], f), file=sys.stderr)
            return 6
        vals.append(v.strip())
    sys.stdout.write(US.join(vals) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
