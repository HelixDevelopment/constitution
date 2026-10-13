#!/usr/bin/env python3
"""tce_normalize_ref.py — reference (independent, from-scratch) comment/
whitespace normaliser for the trivial-equivalence (TCE) mutant-dedup half
of DEC-23, used ONLY by tests/test_mutation_reuse_red.sh (T057,
SpecKit-004 "fast-dev-cycles") to self-validate the
mr_tce_duplicate / mr_tce_distinct fixture pairs under
tests/fixtures/mutation_reuse/ -- BEFORE any claim is made about
gates/mutation_reuse.py's `check-duplicate` subcommand (T-C07), the real
implementation this file MUST NOT be imported by (checked by a control
needle in the RED test's Section A).

Rule (DEC-23 / TCE, R3:36): two mutated gate scripts that differ ONLY in
comment placement, blank lines, or indentation/whitespace encode the SAME
mutation and MUST normalise to the SAME digest (reported DUPLICATE by the
real tool); two scripts that differ in actual executable content (a
different grep pattern, a different comparison) MUST NOT be collapsed
(reported DISTINCT) -- the negative control proving normalisation does not
over-merge genuinely different mutants.

Normalisation, applied line-by-line then joined:
  1. Strip a comment: from the first UNQUOTED '#' to end of line. A '#'
     INSIDE a single- or double-quoted string is preserved verbatim (a
     naive strip-at-first-'#' implementation would corrupt any gate script
     that echoes literal text containing '#' -- proven by the RED test's
     own quote-aware control needle).
  2. Collapse whitespace: leading/trailing whitespace on each line is
     stripped; runs of whitespace OUTSIDE any quoted string collapse to a
     single space (indentation differences, e.g. 4 vs 6 leading spaces
     before an `exit 1`, become identical). Whitespace INSIDE a quoted
     string is preserved verbatim (never collapsed) -- an intentional
     multi-space literal inside an echoed string is content, not layout.
  3. Drop blank lines: a line that normalises to the empty string (a
     genuinely blank line, or a line that was ONLY a comment, such as a
     `#!/bin/sh` shebang or a full-line `# comment`) contributes nothing to
     the joined result -- so two scripts whose only difference is an
     inserted/removed blank line, or a moved full-line comment, still
     collapse to the same digest.
  4. SHA-256 the '\\n'-joined remaining lines (UTF-8, surrogateescape for
     any non-UTF-8 byte a real script might legitimately contain).

Known, documented limitation (not exercised by any fixture this file
self-validates against): quote-state tracking does not understand
backslash-escaped quotes (`\\"` inside a double-quoted string) or here-docs
-- a script relying on either would need a stronger tokenizer than this
reference implementation provides. This is an honest scope boundary
(§11.4.6), not a silently-assumed-covered case.

Usage: tce_normalize_ref.py <script-path>
  Prints the 64-hex-char sha256 digest of the normalised script to stdout,
  exit 0.
  Prints nothing to stdout and a short diagnostic to stderr, exit 1, if the
  file cannot be read.
"""
import hashlib
import sys


def _normalise_line(line: str) -> str:
    """Strip an unquoted trailing comment, collapse unquoted whitespace
    runs to a single space, and strip leading/trailing whitespace -- all
    in one left-to-right scan so quote state is tracked correctly."""
    out = []
    in_dquote = False
    in_squote = False
    pending_space = False

    def emit(ch):
        nonlocal pending_space
        if pending_space:
            out.append(" ")
            pending_space = False
        out.append(ch)

    for ch in line:
        if in_dquote:
            # Inside a double-quoted string: EVERY character, including a
            # literal '#' or literal whitespace, is preserved verbatim --
            # normalisation never touches quoted content.
            out.append(ch)
            if ch == '"':
                in_dquote = False
            continue
        if in_squote:
            out.append(ch)
            if ch == "'":
                in_squote = False
            continue
        if ch == "#":
            # An UNQUOTED '#' starts a comment that runs to end of line --
            # discard the rest of the line entirely (never flush any
            # pending space collected just before it).
            break
        if ch.isspace():
            if out:
                pending_space = True
            # Leading whitespace (out is still empty): silently dropped,
            # never sets pending_space -- this is the leading-whitespace
            # strip half of rule 2.
            continue
        if ch == '"':
            emit(ch)
            in_dquote = True
            continue
        if ch == "'":
            emit(ch)
            in_squote = True
            continue
        emit(ch)

    # Defensive trailing-whitespace strip: pending_space with nothing to
    # flush after it already means no trailing space was ever appended, so
    # this rstrip() is a no-op in practice for this algorithm's own output
    # -- kept as an explicit belt-and-braces per §11.4.201's honest-guard
    # discipline (never rely on an invariant holding by construction alone
    # without a cheap independent check).
    return "".join(out).rstrip()


def normalise_script(text: str) -> str:
    kept_lines = []
    for raw_line in text.splitlines():
        normalised = _normalise_line(raw_line)
        if normalised:
            kept_lines.append(normalised)
    return "\n".join(kept_lines)


def compute_digest(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    normalised = normalise_script(text)
    return hashlib.sha256(
        normalised.encode("utf-8", errors="surrogateescape")
    ).hexdigest()


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: tce_normalize_ref.py <script-path>\n")
        return 2
    try:
        digest = compute_digest(argv[1])
    except OSError as exc:
        sys.stderr.write(f"tce_normalize_ref.py: {exc}\n")
        return 1
    print(digest)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
