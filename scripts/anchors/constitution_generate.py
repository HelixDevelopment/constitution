#!/usr/bin/env python3
"""constitution_generate.py — generate/verify constitution/groups/*.md +
constitution_index.yaml from constitution/Constitution.md.
See specs/003-reorganize-constitution-yaml/contracts/generator-cli.md.
"""
import argparse, hashlib, os, subprocess, sys
from datetime import datetime, timezone

try:
    import yaml
except ImportError:
    sys.stderr.write("FATAL: PyYAML not installed. See check_deps.sh / G-005.\n")
    sys.exit(4)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anchor_lib import extract_anchors, assign_group, UnclassifiedAnchorError, MalformedHeadingError


def _anchor_sort_key(anchor_id: str) -> tuple:
    """Sort key that survives BOTH real sub-anchor suffix forms in the
    corpus: the dotted `.LETTER` form (`11.4.10.A`, Constitution.md:753)
    AND the parenthesized `(LETTER+)` form (`11.4.184(I)`,
    Constitution.md:10279, recognized by the 4th regression fix's Finding
    A) — the naive `tuple(int(x) for x in id.split("."))` crashes on the
    first (`ValueError: invalid literal for int() with base 10: 'A'`), and
    a naive dotted-suffix-only split silently loses the LEADING DIGITS of
    the second: splitting "11.4.184(I)" on "." gives ["11","4","184(I)"],
    and "184(I)".isdigit() is False, so a version of this helper that
    treats any non-digit part as a PURE suffix (verified live: the earlier
    form of this helper) discards the "184" numeric value entirely,
    sorting "11.4.184(I)" before "11.4.183" instead of between "11.4.184"
    and "11.4.185" — confirmed live before this fix. This version extracts
    any LEADING digits from a mixed component (via regex) into the numeric
    tuple, keeping only the true non-numeric remainder (a bare letter, or
    a parenthesized letter-group) as the suffix — so "184(I)" contributes
    both `184` to the numeric tuple AND `"(I)"` as the suffix. Two ids
    sharing the same numeric prefix then order correctly by suffix — ""
    sorts before any non-empty suffix in Python, so "11.4.184" <
    "11.4.184(I)" < "11.4.185" — and ids with different numeric prefixes
    are ordered entirely by that prefix tuple (tuple comparison
    short-circuits on the first differing element)."""
    import re as _re
    numeric_parts = []
    suffix = ""
    for part in anchor_id.split("."):
        if part.isdigit():
            numeric_parts.append(int(part))
        else:
            m = _re.match(r"^(\d*)(.*)$", part)
            digits, rest = m.group(1), m.group(2)
            if digits:
                numeric_parts.append(int(digits))
            suffix = rest
    return (tuple(numeric_parts), suffix)


def _git_commit_of(source_path: str) -> str:
    cwd = os.path.dirname(os.path.abspath(source_path)) or "."
    out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=cwd,
                          capture_output=True, text=True, check=True)
    return out.stdout.strip()


def build_records(source_path: str):
    with open(source_path) as f:
        text = f.read()
    try:
        anchors = extract_anchors(text)
    except MalformedHeadingError as e:
        sys.stderr.write(f"FATAL: malformed anchor heading: {e}\n")
        sys.exit(2)
    seen_lines: dict[str, int] = {}
    records = []
    for a in anchors:
        if a["id"] in seen_lines:
            sys.stderr.write(
                f"FATAL: duplicate anchor id {a['id']!r} at line {a['start_line']} "
                f"(first seen at line {seen_lines[a['id']]})\n"
            )
            sys.exit(3)
        seen_lines[a["id"]] = a["start_line"]
        try:
            group = assign_group(a["id"])
        except UnclassifiedAnchorError:
            sys.stderr.write(f"FATAL: anchor {a['id']!r} matches no group rule\n")
            sys.exit(5)
        records.append({
            "id": a["id"], "title": a["title"], "group": group, "body": a["body"],
            "location": f"constitution/groups/{group}.md#{a['id'].replace('.', '-')}",
        })
    return records


def write_groups(records, groups_dir: str) -> dict:
    os.makedirs(groups_dir, exist_ok=True)
    by_group: dict[str, list] = {}
    for r in records:
        by_group.setdefault(r["group"], []).append(r)
    for group, recs in by_group.items():
        recs.sort(key=lambda r: _anchor_sort_key(r["id"]))
        with open(os.path.join(groups_dir, f"{group}.md"), "w") as f:
            f.write(f"# {group.replace('-', ' ').title()}\n\n")
            for r in recs:
                # A record's "body" (per anchor_lib.extract_anchors's `_close`)
                # already carries, as trailing "\n" characters, EXACTLY the N
                # blank lines that separated it from whatever followed it in
                # the ORIGINAL Constitution.md (join-of-lines semantics: N
                # blank source lines contribute N trailing "\n" chars, no
                # more). Reproducing the SAME body on re-extraction from the
                # regenerated group file — this task's actual acceptance bar
                # — requires exactly ONE further "\n" beyond that (the
                # newline that would end the last blank line and immediately
                # precede whatever comes next), regardless of N. Writing
                # `body + "\n\n"` (as originally drafted) inserts a SECOND,
                # extra blank line beyond what the source ever had, which a
                # subsequent extract_anchors() call over the regenerated file
                # then folds INTO this same record's re-parsed body (its
                # `end_line` is computed as "next heading's line minus one",
                # so it silently sweeps up any extra blank lines written
                # here) — confirmed live: this produced a body with one
                # extra trailing "\n" for every one of the 283 real anchors,
                # first caught on id "7.1" while running T010's byte-identity
                # test, which failed before this fix and passes after it.
                f.write(r["body"] + "\n")
    return {g: len(recs) for g, recs in by_group.items()}


def build_yaml_index(records, group_counts, source_path: str, index_out: str) -> dict:
    index = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generated_from": {"source": "constitution/Constitution.md",
                            "commit": _git_commit_of(source_path)},
        "groups": sorted(
            [{"name": g, "path": f"constitution/groups/{g}.md", "anchor_count": n}
             for g, n in group_counts.items()],
            key=lambda x: x["name"],
        ),
        "anchors": sorted(
            [{"id": r["id"], "title": r["title"], "group": r["group"], "location": r["location"]}
             for r in records],
            key=lambda r: _anchor_sort_key(r["id"]),
        ),
    }
    with open(index_out, "w") as f:
        yaml.safe_dump(index, f, sort_keys=False, allow_unicode=True)
    return index


def cmd_generate(args) -> int:
    records = build_records(args.source)
    group_counts = write_groups(records, args.groups_dir)
    build_yaml_index(records, group_counts, args.source, args.index_out)
    print(f"generated: {len(records)} anchors across {len(group_counts)} groups")
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("generate")
    sp.add_argument("--source", required=True)
    sp.add_argument("--groups-dir", required=True)
    sp.add_argument("--index-out", required=True)
    sp.set_defaults(func=cmd_generate)
    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
