#!/usr/bin/env python3
"""
T057 reference (non-production) normaliser for DEC-23's trivial-equivalence
dedup rule: "A mutation whose applied script is byte-identical (after
comment/whitespace normalisation) to the original or to another mutation is
flagged trivially equivalent/duplicate and reported, not run twice."

Used ONLY by test_mutation_reuse_red.sh's Section D to prove its
mr_tce_duplicate / mr_tce_distinct fixture pair is non-vacuous BEFORE any
claim is made about what the (absent) real mutation_reuse.py tool's
`check-duplicate` subcommand should report. Never claims to BE
mutation_reuse.py.

Normalisation rule (this file's own, defined here per the established house
precedent of a RED test defining a binding-if-adopted contract stub when
none exists -- see test_verdict_cache_red.sh's header comment): for a
POSIX-shell script,
  1. strip every full-line and trailing '#'-comment (a '#' NOT inside a
     single- or double-quoted string),
  2. collapse each line's leading/trailing whitespace,
  3. drop blank lines,
then SHA-256 the resulting byte sequence. This is a minimal, literal
"comment/whitespace normalisation" -- it deliberately does NOT do
AST-level semantic normalisation (variable renaming, statement reordering),
since DEC-23's own text names only "comment/whitespace normalisation", not
full semantic equivalence -- matching the TCE literature DEC-23 cites
(compiler-level trivial-compiler-equivalence, not full program equivalence).

Usage: tce_normalize_ref.py <script_path>
Prints the normalised script's 64-hex-char SHA-256 to stdout and exits 0,
or prints nothing and exits 1 if the file cannot be read.
"""
import hashlib
import sys


def strip_comment(line):
    """Strip a trailing '#'-comment not inside a single/double-quoted string."""
    in_single = False
    in_double = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            return line[:i]
    return line


def normalise(text):
    out_lines = []
    for raw_line in text.splitlines():
        stripped = strip_comment(raw_line).strip()
        if stripped:
            out_lines.append(stripped)
    return "\n".join(out_lines)


def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        sys.exit(1)
    normalised = normalise(text)
    print(hashlib.sha256(normalised.encode("utf-8")).hexdigest())
    sys.exit(0)


if __name__ == "__main__":
    main()
