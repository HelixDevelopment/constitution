#!/usr/bin/env bash
# cm_relocated_anchor_copies_lockstep.sh -- CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP gate
# (§11.4.102(E) honest boundary; §11.4.227(B) lockstep; §11.4.201(6)/(7) control needle; §11.4.35 data).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Some constitution clauses are carried in more than one place: the canonical text in
# Constitution.md, relocated copies (CLAUDE_ANCHORS_FULL.md, the generated group file) and a one-line
# EXTENSION carrier in each core CLAUDE/AGENTS/QWEN/GEMINI.md. This gate keeps them in byte lockstep
# with as little logic as possible: it only COUNTS EXACT BYTE OCCURRENCES.
#   Each row of scripts/gates/relocated_copies_lockstep.tsv names <file>, <pinned> and <count>: the
#   file must hold the exact bytes of the pinned file exactly <count> times (bytes.count, so
#   non-overlapping). The pinned byte strings live in scripts/gates/relocated_copies/ and carry their
#   own boundaries: the clause ends in its newline, the carrier line ends in its newline, a marker
#   starts with the newline before a copy's first line, and the verbatim mandate sits between two
#   spaces. So a drifted copy (any byte: case, whitespace, CRLF, lone CR, trailing space, glued text)
#   lowers the clause count, a drifted or duplicated extra copy raises the marker count, and a
#   mid-line citation of a copy's opening words is not counted (it has no newline before it).
#   Files are read as bytes; nothing is normalised.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_relocated_anchor_copies_lockstep.sh [--root DIR]
#     --root  constitution root (default: two levels above this script)
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS  -- every row holds.
#   1 FAIL  -- at least one row does not hold; every failing row is printed with its file, pinned
#              file, the count found and the count declared.
#   2 BLIND -- python3 not usable, a bad argument, the data file or a named file unreadable (missing,
#              a directory, no permission), no row, a malformed row (not exactly three non-empty
#              TAB-separated fields with a decimal count), or an empty pinned file. Never a pass.
#
# ── Control needle (§11.4.201(7)(b), §11.4.273) ──────────────────────────────
#   Rows with a count >= 1 are positive controls: an instrument that cannot see a copy reports a
#   count FAIL, never silence.
#
# ── Mutation test ────────────────────────────────────────────────────────────
#   cm_relocated_anchor_copies_lockstep_mutation_test.sh holds a hand-written mutant for EVERY
#   non-comment line of this file (whole-line replacements), each of which must be killed, and it
#   FAILs when a line of this file has no mutant or when a mutant's original line no longer occurs
#   exactly once. Any edit to a line below therefore fails that test until its mutants are rewritten.
#   Keep this file small and keep every line unique.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# Classification: universal mechanism (§11.4.17); the declared rows and pinned strings are DATA (§11.4.35).
command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND -- python3 not usable"; exit 2; }
exec python3 -I - "$(cd "$(dirname "$0")/../.." && pwd)" "$@" <<'PY'
import sys
GATE, DECL = "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP", b"scripts/gates/relocated_copies_lockstep.tsv"
def blind(msg):
    print(f"{GATE}: BLIND -- {msg}")
    sys.exit(2)
args = sys.argv[1:]
if len(args) == 3 and args[1] == "--root":
    args = args[2:]
if len(args) != 1:
    blind("usage: cm_relocated_anchor_copies_lockstep.sh [--root DIR]")
def read(rel):
    try:
        with open(args[0].encode() + b"/" + rel, "rb") as fh:
            return fh.read()
    except OSError as err:
        blind(f"{rel.decode(errors='replace')} is not readable ({err.strerror})")
rows = [row.split(b"\t") for row in read(DECL).split(b"\n") if row and not row.startswith(b"#")]
if not rows:
    blind(f"{DECL.decode()} declares no row")
failed = 0
for row in rows:
    if len(row) != 3 or not row[0] or not row[1] or not row[2].isdigit():
        blind(f"{DECL.decode()}: malformed row {row!r}")
    haystack, pinned = read(row[0]), read(row[1])
    if not pinned:
        blind(f"{row[1].decode(errors='replace')} is empty")
    found = haystack.count(pinned)
    if found != int(row[2]):
        print(f"{GATE}: FAIL -- {row[0].decode(errors='replace')} holds {row[1].decode(errors='replace')} {found} time(s), declared {int(row[2])}")
        failed += 1
if failed:
    sys.exit(1)
print(f"{GATE}: PASS -- {len(rows)} row(s) hold their declared exact byte counts")
PY
