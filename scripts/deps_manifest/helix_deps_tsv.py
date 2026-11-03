#!/usr/bin/env python3
"""helix_deps_tsv.py - ONE structural helix-deps.yaml reader for bash consumers (constitution 11.4.31).

Purpose
    Emit one record per `deps[]` entry, taken strictly from the PARSED YAML structure (PyYAML via the
    11.4.31 verifier's StrictLoader: all scalars strings, duplicate keys refused). Replaces every
    hand-written line parser (round-3 finding: bare `-`, quoted keys, `key :` and duplicate keys fooled them).
Usage
    python3 -I helix_deps_tsv.py <manifest>
Output (stdout): one line per dep, fields separated by US (0x1f; non-whitespace so empty fields survive
    `IFS=$'\\x1f' read`): name, path, ssh_url, ref, third_party ("1" iff the scalar is exactly `true`, else "0").
Exit codes
    0 ok (possibly zero deps) | 3 PyYAML unavailable (or HELIX_DEPS_TSV_FORCE_NO_YAML=1, test switch only, honoured only with HELIX_TEST_MODE=1)
    4 unreadable / unparseable / duplicate key / multi-document | 6 unknown shape (top level not a mapping,
    deps not a list or null, a dep not a mapping, a scalar field that is not a string, a field value containing
    any C0 control char or DEL, incl. NUL/US/newline/CR). Diagnostics on stderr. Read-only; no network; no execution of manifest content.
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
    if len(argv) != 2:
        print("usage: helix_deps_tsv.py <manifest>", file=sys.stderr)
        return 4
    if os.environ.get("HELIX_DEPS_TSV_FORCE_NO_YAML") == "1" and os.environ.get("HELIX_TEST_MODE") == "1":
        print("helix_deps_tsv: PyYAML unavailable (forced by test switch)", file=sys.stderr)
        return 3
    try:
        import helix_deps_manifest as hm
    except Exception as exc:
        print("helix_deps_tsv: cannot import parser: %s" % exc, file=sys.stderr)
        return 3
    if hm.yaml is None:
        print("helix_deps_tsv: PyYAML unavailable", file=sys.stderr)
        return 3
    try:
        with open(argv[1], "rb") as fh:
            raw = fh.read(MAXB + 1)
        if len(raw) > MAXB:
            print("helix_deps_tsv: manifest larger than 1 MiB", file=sys.stderr)
            return 4
        text = raw.decode("utf-8")
    except Exception as exc:
        print("helix_deps_tsv: unreadable: %s" % exc, file=sys.stderr)
        return 4
    doc, err = hm.load_manifest_text(text)
    if err:
        print("helix_deps_tsv: %s" % err, file=sys.stderr)
        return 4
    if not isinstance(doc, dict):
        print("helix_deps_tsv: top level is not a mapping", file=sys.stderr)
        return 6
    deps = doc.get("deps", "")
    if deps in ("", None):
        deps = []
    if not isinstance(deps, list):
        print("helix_deps_tsv: deps is not a list", file=sys.stderr)
        return 6
    out = []
    for i, d in enumerate(deps):
        if not isinstance(d, dict):
            print("helix_deps_tsv: deps[%d] is not a mapping" % i, file=sys.stderr)
            return 6
        vals = []
        for k in ("name", "path", "ssh_url", "ref"):
            v = d.get(k, "")
            if not isinstance(v, str) or _bad_value(v):
                print("helix_deps_tsv: deps[%d].%s has an unusable value" % (i, k), file=sys.stderr)
                return 6
            vals.append(v.strip())
        tp = d.get("third_party", "")
        if not isinstance(tp, str):
            print("helix_deps_tsv: deps[%d].third_party is not a scalar" % i, file=sys.stderr)
            return 6
        vals.append("1" if tp.strip() == "true" else "0")
        out.append(US.join(vals))
    sys.stdout.write("".join(l + "\n" for l in out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
