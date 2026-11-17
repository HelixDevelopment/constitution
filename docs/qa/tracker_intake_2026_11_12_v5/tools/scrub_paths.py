#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_12_v5/tools/scrub_paths.py -- copy a captured run into this
directory with the host's scratch paths replaced by fixed placeholders, so the evidence names no
home directory or session path (the lint's EPHEMERAL rule, applied to the evidence itself).

usage: scrub_paths.py <in> <out> --root <path>=<placeholder> [--root ...]
  Each --root is replaced literally, longest first; then every mktemp-style directory name
  (`tmp.` followed by ten characters, and the mktemp -d names of python's tempfile, `tmp` plus
  eight lowercase or digit characters) becomes `<tmp>`. The output ends with one line naming the
  replacements made, so a reader can tell the copy from the capture. Exit: 0 written; 2 usage.
Evidence class: gate-logic only (section 11.4.289).
"""
import re
import sys


def main(argv):
    if len(argv) < 4 or (len(argv) - 2) % 2:
        print("usage: scrub_paths.py <in> <out> --root <path>=<placeholder> [--root ...]", file=sys.stderr)
        return 2
    src, dst, rest = argv[0], argv[1], argv[2:]
    roots = []
    for flag, spec in zip(rest[0::2], rest[1::2]):
        if flag != "--root" or "=" not in spec:
            print("usage: --root <path>=<placeholder>", file=sys.stderr)
            return 2
        path, ph = spec.split("=", 1)
        if not path.startswith("/"):
            print("usage: a root must be an absolute path", file=sys.stderr)
            return 2
        roots.append((path, ph))
    text = open(src, encoding="utf-8", errors="surrogateescape").read()
    counts = []
    for path, ph in sorted(roots, key=lambda r: -len(r[0])):
        counts.append("%s x%d" % (ph, text.count(path)))
        text = text.replace(path, ph)
    text, n = re.subn(r"(?<![\w.])tmp(?:\.[A-Za-z0-9]{10}|[a-z0-9_]{8})(?![\w])", "<tmp>", text)
    counts.append("<tmp> x%d" % n)
    with open(dst, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(text)
        if not text.endswith("\n"):
            f.write("\n")
        f.write("# scrubbed copy (tools/scrub_paths.py): %s\n" % ", ".join(counts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
