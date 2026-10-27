#!/usr/bin/env python3
"""status_summary_archive.py -- keep the `Status summary` cell of a governance carrier a one-line hook.

Why this exists
  Section 11.4.61(A) defines the `Status summary` row of the metadata table as a "one-line current-state hook".
  Amendment after amendment appended to the cell instead, so the preamble of CLAUDE.md / AGENTS.md / Constitution.md
  (everything before the first `## ` heading, which `head`, a nested-memory load or any quick read pays first) grew
  to 130-160 KB each, almost all of it the cell.  This tool moves the older entries out of the always-loaded
  preamble into an on-demand Markdown archive, losslessly, and leaves one-line pointer text in the cell.

Cell format after a move
  | Status summary | <newest entry> Older entries of this cell ... <archive path> ... |
  The newest entry is the text up to the first ` Prior: ` / ` Prior round: ` marker.  Everything after it is the
  moved text; it is split into one archive entry per marker (entries joined with ONE space are byte-identical to
  the moved text, which is what `verify` re-checks).  A later rotation prepends the newly moved entries to the
  archive (newest first) and refreshes the header figures.

Commands
  archive --carrier FILE --archive FILE [--bump-revision] [--dry-run]
      rewrites the carrier cell and the archive (both atomically, archive first); exit 0 ok / 2 usage-or-format error
  verify  --carrier FILE --archive FILE
      exit 0 when the cell is compact, points at the archive, and the archive header figures match its entries;
      exit 1 naming each failed check

The archive path written into the cell is the archive's path relative to the carrier's directory.

Classification: universal (Constitution 11.4.17) -- no consuming-project data.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

CELL_PREFIX = "| Status summary | "
CELL_SUFFIX = " |"
POINTER_MARK = " Older entries of this cell"
ENTRY_MARKER_RE = re.compile(r" (?:Prior round:|Prior:) ")
ENTRY_SPLIT_RE = re.compile(r" (?=(?:Prior round:|Prior:) )")
BEGIN = "<!-- BEGIN ENTRIES -->"
END = "<!-- END ENTRIES -->"
FIG_ENTRIES = "- Entries: "
FIG_BYTES = "- Bytes of moved text: "
FIG_SHA = "- sha256 of moved text: "


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def pointer_sentence(rel_path: str) -> str:
    return (
        f"{POINTER_MARK} (verbatim, none dropped) are kept on demand in {rel_path}; per §11.4.61(A) this cell is a "
        "one-line current-state hook, so record each new amendment in CHANGELOG.md and, when this cell grows, "
        "rotate it with scripts/amendment_log/status_summary_archive.py."
    )


def find_cell(lines: list[str]) -> int:
    """Index of the single `| Status summary | ... |` row inside the preamble (before the first `## ` heading)."""
    hits = []
    for i, line in enumerate(lines):
        if line.startswith("## "):
            break
        if line.startswith(CELL_PREFIX):
            hits.append(i)
    if len(hits) != 1:
        raise ValueError(f"expected exactly one Status summary row in the preamble, found {len(hits)}")
    if not lines[hits[0]].endswith(CELL_SUFFIX):
        raise ValueError("the Status summary row does not end with ' |'")
    return hits[0]


def split_body(body: str) -> tuple[str, str, str]:
    """-> (kept newest entry, moved text, existing pointer text or '')."""
    pointer = ""
    if POINTER_MARK in body:
        body, pointer = body.split(POINTER_MARK, 1)
        pointer = POINTER_MARK + pointer
    m = ENTRY_MARKER_RE.search(body)
    if not m:
        return body, "", pointer
    return body[: m.start()], body[m.start() + 1 :], pointer


def split_entries(moved: str) -> list[str]:
    entries = ENTRY_SPLIT_RE.split(moved)
    if " ".join(entries) != moved:  # exactness proof, never a silent loss
        raise ValueError("entry split is not reversible")
    return entries


def read_archive(path: Path) -> tuple[str, list[str]]:
    text = path.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        raise ValueError(f"{path}: missing {BEGIN} / {END}")
    head = text.split(BEGIN, 1)[0]
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    return head, [ln for ln in block.split("\n") if ln.strip()]


def figures(entries: list[str]) -> tuple[int, int, str]:
    joined = " ".join(entries)
    return len(entries), len(joined.encode("utf-8")), sha256_hex(joined)


def render_archive(carrier_name: str, entries: list[str], revision: int, created: str, now: str) -> str:
    n, b, h = figures(entries)
    rows = [
        f"# Status summary archive -- {carrier_name}",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| Revision | {revision} |",
        f"| Created | {created} |",
        f"| Last modified | {now} |",
        "| Status | active |",
        f"| Status summary | Verbatim archive of the older entries of the `Status summary` cell of `{carrier_name}`. |",
        "| Issues | none |",
        "| Issues summary | -- |",
        "| Fixed | the always-loaded preamble no longer carries the amendment log |",
        "| Fixed summary | Section 11.4.61(A) defines the cell as a one-line hook; the log was moved here without loss. |",
        "| Continuation | rotate again with `scripts/amendment_log/status_summary_archive.py archive` when the cell grows |",
        "",
        f"This file holds the older entries of the `Status summary` cell of `{carrier_name}`, newest first, one entry per",
        "paragraph, exactly as they stood in the cell. They were moved out of the always-loaded preamble because that",
        "preamble is paid on every `head`, nested-memory load or quick read of the carrier. Nothing was dropped: the",
        "entries below, joined with ONE space, are byte-identical to the moved text, and the figures below are re-checked",
        "by `scripts/amendment_log/status_summary_archive.py verify`.",
        "",
        f"{FIG_ENTRIES}{n}",
        f"{FIG_BYTES}{b}",
        f"{FIG_SHA}{h}",
        "",
        "## Entries (newest first)",
        "",
        BEGIN,
        "",
    ]
    for e in entries:
        rows += [e, ""]
    rows += [END, ""]
    return "\n".join(rows)


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
        mode = path.stat().st_mode & 0o7777 if path.exists() else 0o644
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def rel_pointer(carrier: Path, archive: Path) -> str:
    return os.path.relpath(archive.resolve(), carrier.resolve().parent).replace(os.sep, "/")


def bump_revision(lines: list[str], now: str) -> None:
    for i, line in enumerate(lines):
        if line.startswith("## "):
            break
        m = re.fullmatch(r"\| Revision \| (\d+) \|", line)
        if m:
            lines[i] = f"| Revision | {int(m.group(1)) + 1} |"
        elif line.startswith("| Last modified | "):
            lines[i] = f"| Last modified | {now} |"


def cmd_archive(args: argparse.Namespace) -> int:
    carrier, archive = Path(args.carrier), Path(args.archive)
    text = carrier.read_text(encoding="utf-8")
    lines = text.split("\n")
    try:
        idx = find_cell(lines)
    except ValueError as exc:
        print(f"status_summary_archive: {carrier}: {exc}", file=sys.stderr)
        return 2
    body = lines[idx][len(CELL_PREFIX) : -len(CELL_SUFFIX)]
    kept, moved, _pointer = split_body(body)
    if not kept.strip():
        print(f"status_summary_archive: {carrier}: the newest entry is empty, refusing", file=sys.stderr)
        return 2
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    new_entries: list[str] = []
    if moved:
        try:
            new_entries = split_entries(moved)
        except ValueError as exc:
            print(f"status_summary_archive: {carrier}: {exc}", file=sys.stderr)
            return 2
    old_entries: list[str] = []
    revision, created = 1, now[:10]
    if archive.exists():
        try:
            head, old_entries = read_archive(archive)
        except ValueError as exc:
            print(f"status_summary_archive: {exc}", file=sys.stderr)
            return 2
        mrev = re.search(r"^\| Revision \| (\d+) \|$", head, re.M)
        mcre = re.search(r"^\| Created \| (\S+) \|$", head, re.M)
        if mrev and mcre:
            revision, created = int(mrev.group(1)) + 1, mcre.group(1)
    entries = new_entries + old_entries
    new_body = kept + pointer_sentence(rel_pointer(carrier, archive))
    if not new_entries and entries and (CELL_PREFIX + new_body + CELL_SUFFIX) == lines[idx]:
        print(f"status_summary_archive: {carrier}: already compact, nothing to move")
        return 0
    if not entries:
        print(f"status_summary_archive: {carrier}: no older entries to archive", file=sys.stderr)
        return 2
    lines[idx] = CELL_PREFIX + new_body + CELL_SUFFIX
    if args.bump_revision:
        bump_revision(lines, now)
    new_text = "\n".join(lines)
    before = len(text.encode("utf-8"))
    after = len(new_text.encode("utf-8"))
    print(
        f"status_summary_archive: {carrier.name}: moved {len(new_entries)} entr{'y' if len(new_entries) == 1 else 'ies'} "
        f"({len(moved.encode('utf-8'))} bytes) to {archive}; file {before} -> {after} bytes"
    )
    if args.dry_run:
        return 0
    atomic_write(archive, render_archive(carrier.name, entries, revision, created, now))
    atomic_write(carrier, new_text)
    return cmd_verify(args)


def cmd_verify(args: argparse.Namespace) -> int:
    carrier, archive = Path(args.carrier), Path(args.archive)
    failures: list[str] = []
    try:
        lines = carrier.read_text(encoding="utf-8").split("\n")
        idx = find_cell(lines)
        body = lines[idx][len(CELL_PREFIX) : -len(CELL_SUFFIX)]
    except (OSError, ValueError) as exc:
        print(f"status_summary_archive verify: FAIL carrier: {exc}")
        return 1
    kept, moved, pointer = split_body(body)
    if moved:
        failures.append("cell is not compact: older entries (' Prior: ' / ' Prior round: ') are still inline")
    if not pointer:
        failures.append(f"cell carries no '{POINTER_MARK.strip()}' pointer text")
    want = rel_pointer(carrier, archive)
    if pointer and want not in pointer:
        failures.append(f"cell pointer does not name the archive path {want}")
    if not archive.is_file():
        failures.append(f"archive {archive} is missing")
    else:
        try:
            head, entries = read_archive(archive)
        except ValueError as exc:
            failures.append(str(exc))
            entries = []
            head = ""
        if not entries:
            failures.append("archive holds no entries")
        else:
            n, b, h = figures(entries)
            for label, got, wantfig in (
                (FIG_ENTRIES, n, None),
                (FIG_BYTES, b, None),
                (FIG_SHA, h, None),
            ):
                m = re.search("^" + re.escape(label) + r"(\S+)$", head, re.M)
                if not m or m.group(1) != str(got):
                    failures.append(f"archive header figure '{label.strip('- :').strip()}' is {m.group(1) if m else 'absent'}, entries give {got}")
            if any(not (e.startswith("Prior:") or e.startswith("Prior round:")) for e in entries):
                failures.append("an archive entry does not start with a Prior marker")
    if failures:
        for f in failures:
            print(f"status_summary_archive verify: FAIL {f}")
        return 1
    print(f"status_summary_archive verify: PASS {carrier.name} -> {archive.name} ({n} entries, {b} bytes, sha256 {h[:16]}...)")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("archive", "verify"):
        p = sub.add_parser(name)
        p.add_argument("--carrier", required=True)
        p.add_argument("--archive", required=True)
        if name == "archive":
            p.add_argument("--bump-revision", action="store_true")
            p.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    return cmd_archive(args) if args.cmd == "archive" else cmd_verify(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
