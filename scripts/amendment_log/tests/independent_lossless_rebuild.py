#!/usr/bin/env python3
"""independent_lossless_rebuild.py -- prove a Status-summary move lossless WITHOUT importing the tool that did it.

Why this exists
    scripts/amendment_log/status_summary_archive.py moves the older entries of the `Status summary` cell of a carrier into
    an archive and its own `verify` re-checks the archive. A proof produced by the tool that made the change shares the
    tool's blind spots (Constitution 11.4.249: producer != verifier). This script re-derives the claim from bytes only:
    it imports nothing from the tool, parses the carrier and the archive with its own few lines, and compares them with
    the carrier as it stood BEFORE the move.

Usage
    python3 -I independent_lossless_rebuild.py <pre-change-carrier> <post-change-carrier> <archive>
    python3 -I independent_lossless_rebuild.py --figures-only <post-change-carrier> <archive>

Checks (full mode)
    1. The pre-change `| Status summary | ... |` row is rebuilt as
       `| Status summary | ` + kept text + ` ` + (archive entries joined with ONE space) + ` |` and must equal the
       pre-change row byte for byte (bytes + sha256 printed).
    2. Every other line of the carrier is byte-identical before and after, except `| Revision |` (+1 when it changed) and
       `| Last modified |`; the line count is unchanged; so the body below the first heading is untouched.
    3. The archive's own header figures (Entries, Bytes of moved text, sha256 of moved text) are re-computed from its entry
       block and must match.
    4. Negative controls: one byte of the middle entry is changed in memory and the SAME functions that decide checks 1 and 3
       (is_lossless, figures_match) must then reject it, so a check mutated to always say "lossless" fails this script on
       its own good input.
    --figures-only runs checks 3 and 4 (4 against the archive digest) plus "the cell is a compact one-line hook"; it is the
    only proof available once the pre-change carrier is no longer at hand.

Exit codes
    0 every check passed | 1 a check failed | 2 usage or format error (no/several Status summary rows, no entry markers, ...)
Dependencies
    python3 standard library only. Writes nothing.
Classification: universal (Constitution 11.4.17).
"""
import hashlib
import re
import sys

CELL = "| Status summary | "
POINTER = " Older entries of this cell"


def die(msg, code=2):
    print("independent_lossless_rebuild: " + msg, file=sys.stderr)
    sys.exit(code)


def read(path):
    try:
        with open(path, encoding="utf-8", newline="") as fh:
            return fh.read()
    except OSError as exc:
        die("cannot read %s: %s" % (path, exc))


def preamble_cell_index(lines, label):
    end = next((i for i, l in enumerate(lines) if l.startswith("## ")), len(lines))
    idx = [i for i in range(end) if lines[i].startswith(CELL)]
    if len(idx) != 1:
        die("%s: %d Status summary rows before the first heading (need exactly 1)" % (label, len(idx)))
    if not lines[idx[0]].endswith(" |"):
        die("%s: the Status summary row does not end with ' |'" % label)
    return idx[0]


def archive_entries(archive_text):
    if "<!-- BEGIN ENTRIES -->" not in archive_text or "<!-- END ENTRIES -->" not in archive_text:
        die("archive has no BEGIN/END ENTRIES markers")
    block = archive_text.split("<!-- BEGIN ENTRIES -->", 1)[1].split("<!-- END ENTRIES -->", 1)[0]
    return [e for e in block.split("\n") if e.strip()]


def header_figures(archive_text):
    try:
        n = int(re.search(r"^- Entries: (\d+)$", archive_text, re.M).group(1))
        b = int(re.search(r"^- Bytes of moved text: (\d+)$", archive_text, re.M).group(1))
        h = re.search(r"^- sha256 of moved text: ([0-9a-f]{64})$", archive_text, re.M).group(1)
    except AttributeError:
        die("archive header figures (Entries / Bytes of moved text / sha256 of moved text) not found")
    return n, b, h


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def row_of(kept, entries):
    """The pre-change row as it must be rebuilt: kept text, then every archived entry joined with ONE space."""
    return CELL + kept + " " + " ".join(entries) + " |"


def is_lossless(orig_row, kept, entries):
    return row_of(kept, entries) == orig_row


def figures_match(n, b, h, entries):
    moved = " ".join(entries)
    return n == len(entries) and b == len(moved.encode("utf-8")) and h == sha(moved)


def corrupt_middle(entries):
    """One byte of the middle entry changed: the control the checks above must NOT accept (instrument can see)."""
    out = list(entries)
    k = len(out) // 2
    out[k] = out[k][:-1] + ("X" if out[k][-1] != "X" else "Y")
    return out, k


def figures_checks(archive_text, entries, carrier_lines, cell_i):
    ok = True
    moved = " ".join(entries)
    n, b, h = header_figures(archive_text)
    good = figures_match(n, b, h, entries)
    print("3. archive header entries=%d bytes=%d vs recomputed entries=%d bytes=%d sha256 %s -> %s" % (
        n, b, len(entries), len(moved.encode("utf-8")), "match" if h == sha(moved) else "DIFFERENT", "OK" if good else "BAD"))
    ok &= good
    starts = all(e.startswith(("Prior: ", "Prior round: ")) for e in entries)
    print("   every entry starts with a Prior marker: %s" % ("OK" if starts else "BAD"))
    ok &= starts
    mutated, k = corrupt_middle(entries)
    neg = not figures_match(n, b, h, mutated)
    print("4. negative control (entry %d changed by one byte) is REJECTED by the figures check: %s" % (k, "OK" if neg else "BAD"))
    ok &= neg
    cell = carrier_lines[cell_i]
    compact = len(cell.encode("utf-8")) < 1200 and POINTER in cell
    print("   cell is a compact one-line hook with the pointer (%d bytes): %s" % (len(cell.encode("utf-8")), "OK" if compact else "BAD"))
    ok &= compact
    return ok


def main(argv):
    if argv and argv[0] == "--figures-only":
        if len(argv) != 3:
            die("usage: --figures-only <post-change-carrier> <archive>")
        new_lines = read(argv[1]).split("\n")
        archive_text = read(argv[2])
        ci = preamble_cell_index(new_lines, argv[1])
        entries = archive_entries(archive_text)
        ok = figures_checks(archive_text, entries, new_lines, ci)
        print("RESULT:", "ALL OK" if ok else "FAILED")
        return 0 if ok else 1
    if len(argv) != 3:
        die("usage: independent_lossless_rebuild.py <pre-change-carrier> <post-change-carrier> <archive>")
    pre_lines = read(argv[0]).split("\n")
    new_lines = read(argv[1]).split("\n")
    archive_text = read(argv[2])
    ip = preamble_cell_index(pre_lines, argv[0])
    inew = preamble_cell_index(new_lines, argv[1])
    ok = True
    if ip != inew:
        print("1. the Status summary row moved from line %d to line %d -> BAD" % (ip + 1, inew + 1))
        ok = False
    orig_row = pre_lines[ip]
    new_row = new_lines[inew]
    kept = new_row[len(CELL):-2].split(POINTER, 1)[0]
    entries = archive_entries(archive_text)

    rebuilt = row_of(kept, entries)
    lossless = is_lossless(orig_row, kept, entries)
    print("1. pre-change row  bytes=%d sha256=%s" % (len(orig_row.encode("utf-8")), sha(orig_row)))
    print("   rebuilt row     bytes=%d sha256=%s -> %s" % (len(rebuilt.encode("utf-8")), sha(rebuilt), "LOSSLESS" if lossless else "MISMATCH"))
    ok &= lossless

    if len(pre_lines) != len(new_lines):
        print("2. line count changed %d -> %d -> BAD" % (len(pre_lines), len(new_lines)))
        ok = False
    else:
        differing = []
        for i, (a, b) in enumerate(zip(pre_lines, new_lines)):
            if i != ip and a != b:
                m = re.match(r"\| ([A-Za-z ]+) \|", a)
                differing.append(m.group(1) if m else "line %d" % (i + 1))
        rev_pre = re.search(r"^\| Revision \| (\d+) \|$", "\n".join(pre_lines[:60]), re.M)
        rev_new = re.search(r"^\| Revision \| (\d+) \|$", "\n".join(new_lines[:60]), re.M)
        rev_ok = True
        if "Revision" in differing:
            rev_ok = bool(rev_pre and rev_new and int(rev_new.group(1)) == int(rev_pre.group(1)) + 1)
        legal = set(differing) <= {"Revision", "Last modified"} and rev_ok
        print("2. other lines that differ: %s (Revision %s -> %s) -> %s" % (
            sorted(differing) or "none", rev_pre.group(1) if rev_pre else "?", rev_new.group(1) if rev_new else "?", "OK" if legal else "BAD"))
        ok &= legal

    ok &= figures_checks(archive_text, entries, new_lines, inew)

    corrupted, k = corrupt_middle(entries)
    detected = not is_lossless(orig_row, kept, corrupted)
    print("   negative control (entry %d corrupted) is REJECTED by the lossless check: %s" % (k, "OK" if detected else "BAD"))
    ok &= detected
    print("RESULT:", "ALL OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
