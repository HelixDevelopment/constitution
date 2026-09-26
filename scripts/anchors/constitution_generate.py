#!/usr/bin/env python3
"""constitution_generate.py — generate/verify constitution/groups/*.md +
constitution_index.yaml from constitution/Constitution.md.
See specs/003-reorganize-constitution-yaml/contracts/generator-cli.md.
"""
import argparse, hashlib, os, shutil, subprocess, sys
from datetime import datetime, timezone

try:
    import yaml
except ImportError:
    # Exit code 5 per contracts/generator-cli.md's own exit-code table
    # (G-005 == "Missing required dependency" == code 5). A prior version
    # of this branch used exit(4), which the contract instead reserves for
    # G-004 (hand-edit divergence, check-mode-only) — confirmed wrong via a
    # T010+T011 independent review's fault injection (I-2 finding) that
    # directly read the contract's table rather than assuming the code
    # written here was already correct.
    sys.stderr.write("FATAL: PyYAML not installed. See check_deps.sh / G-005.\n")
    sys.exit(5)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anchor_lib import extract_anchors, assign_group, derive_metadata, UnclassifiedAnchorError, MalformedHeadingError


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
    # Fixed 2026-09-26 (found via T016's own synthetic-fixture test, which is
    # the first caller in this whole plan to pass a --source path OUTSIDE any
    # git repository): `check=True` on a `git rev-parse HEAD` run from a
    # non-git cwd raises an UNCAUGHT CalledProcessError (exit 128), crashing
    # the entire `generate`/`check` invocation with a raw Python traceback
    # instead of a controlled outcome — flagged as a pre-existing, then-
    # unexercised Minor finding (M-3) in the T010/T011 review, now genuinely
    # triggered. The commit hash is provenance-only metadata (§11.4.6 — never
    # fabricated); an honest "unknown" sentinel when the source has no git
    # history is correct, not a silently-degraded guess.
    cwd = os.path.dirname(os.path.abspath(source_path)) or "."
    out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=cwd,
                          capture_output=True, text=True, check=False)
    if out.returncode != 0:
        return "unknown"
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
            # Exit code 6 — a NEW code, added by controller ruling (T010/
            # T011 review finding I-2): contracts/generator-cli.md's G-001
            # .. G-005 table has NO row at all for "anchor matches no group
            # rule" (this condition is orthogonal to every G-00N clause —
            # it is neither a malformed heading (G-002), a duplicate id
            # (G-003), a hand-edit divergence (G-004, check-mode-only), nor
            # a missing dependency (G-005)). Reusing the dependency code
            # (5, this branch's OWN prior — and wrong — value before this
            # fix) would collide with G-005 the moment both conditions are
            # possible in the same run. 6 is the lowest integer the
            # contract's 0-5 table leaves free. See generator-cli.md's new
            # G-008 clause for the corresponding contract-side ruling.
            sys.stderr.write(f"FATAL: anchor {a['id']!r} matches no group rule\n")
            sys.exit(6)
        meta = derive_metadata(a["body"])
        records.append({
            "id": a["id"], "title": a["title"], "group": group, "body": a["body"],
            "location": f"constitution/groups/{group}.md#{a['id'].replace('.', '-')}",
            **meta,
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


def _source_content_hash(source_path: str) -> str:
    # Added 2026-09-26 (T013/T014 review remediation, Important-1 fix
    # attempt #2): a git-commit-hash comparison (the first attempt) cannot
    # distinguish "source content genuinely changed" from "source unchanged"
    # for a --source outside any git repo (both compare equal via the
    # honest "unknown" sentinel, regardless of real content changes —
    # caught directly by this fix's OWN new drift-detection test, which
    # uses a non-git synthetic source specifically to prove the two-way
    # distinction and found the git-commit approach silently broken for
    # that case) — and is ALSO vulnerable, for a genuinely git-tracked
    # source, to an UNRELATED commit elsewhere in the same repository
    # changing HEAD without touching the source file's own bytes at all,
    # which would report false drift. Hashing the source file's OWN
    # content directly answers "did THIS file's bytes change" precisely,
    # independent of git history and unaffected by unrelated commits.
    with open(source_path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def build_yaml_index(records, group_counts, source_path: str, index_out: str) -> dict:
    index = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generated_from": {"source": "constitution/Constitution.md",
                            "commit": _git_commit_of(source_path),
                            "source_sha256": _source_content_hash(source_path)},
        "groups": sorted(
            [{"name": g, "path": f"constitution/groups/{g}.md", "anchor_count": n}
             for g, n in group_counts.items()],
            key=lambda x: x["name"],
        ),
        "anchors": sorted(
            [{"id": r["id"], "title": r["title"], "group": r["group"], "location": r["location"],
              "classification": r["classification"], "propagation_gate": r["propagation_gate"],
              "binds_principle": r["binds_principle"], "cross_references": r["cross_references"]}
             for r in records],
            key=lambda r: _anchor_sort_key(r["id"]),
        ),
    }
    with open(index_out, "w") as f:
        yaml.safe_dump(index, f, sort_keys=False, allow_unicode=True)
    return index


def cmd_generate(args) -> int:
    # T014 [US3]: write to a SCRATCH directory/file first and only move into
    # place on full success, so a mid-generation failure (e.g. a later
    # anchor's malformed heading, discovered only after earlier groups were
    # already written) can NEVER leave the real --groups-dir/--index-out
    # holding a partial result — G-002's "write NO output file" guarantee,
    # which build_records's own early sys.exit(2)/(3)/(6) already satisfies
    # for THAT function's own scope, but write_groups/build_yaml_index
    # writing DIRECTLY to the real paths would not (a later exit inside one
    # of those two calls would leave whatever the FIRST one already wrote).
    records = build_records(args.source)  # raises/exits BEFORE any disk write on malformed input
    scratch = args.groups_dir + ".scratch"
    if os.path.exists(scratch):
        shutil.rmtree(scratch)
    group_counts = write_groups(records, scratch)
    build_yaml_index(records, group_counts, args.source, args.index_out + ".scratch")
    if os.path.exists(args.groups_dir):
        shutil.rmtree(args.groups_dir)
    os.rename(scratch, args.groups_dir)
    os.replace(args.index_out + ".scratch", args.index_out)
    print(f"generated: {len(records)} anchors across {len(group_counts)} groups")
    return 0


def _content_hash(index: dict) -> str:
    # generated_at is provenance-only per data-model.md's Determinism rule —
    # excluded from the comparison hash so two runs a second apart still agree.
    payload = {k: v for k, v in index.items() if k != "generated_at"}
    return hashlib.sha256(yaml.safe_dump(payload, sort_keys=True).encode()).hexdigest()


def _diverged_index_fields(fresh_index: dict, committed_index: dict) -> list:
    """Field-level naming for a YAML-index divergence (T013/T014 review
    finding Important-2 — G-004's clause text requires "naming the diverged
    field(s)", which the original single generic FATAL message did not do).
    Top-level keys first (schema_version/generated_from/groups/anchors);
    for `anchors` specifically, additionally names which anchor id(s)
    diverged (present-only-in-one-side ids reported as such, changed ids by
    id) — proportionate detail without a full recursive diff."""
    diffs = []
    fresh_cmp = {k: v for k, v in fresh_index.items() if k != "generated_at"}
    committed_cmp = {k: v for k, v in committed_index.items() if k != "generated_at"}
    for key in sorted(set(fresh_cmp) | set(committed_cmp)):
        if fresh_cmp.get(key) == committed_cmp.get(key):
            continue
        if key == "anchors":
            fresh_by_id = {a["id"]: a for a in fresh_cmp.get("anchors", [])}
            committed_by_id = {a["id"]: a for a in committed_cmp.get("anchors", [])}
            only_fresh = sorted(set(fresh_by_id) - set(committed_by_id))
            only_committed = sorted(set(committed_by_id) - set(fresh_by_id))
            changed = sorted(
                aid for aid in (set(fresh_by_id) & set(committed_by_id))
                if fresh_by_id[aid] != committed_by_id[aid]
            )
            if only_fresh:
                diffs.append(f"anchors: present in a fresh generate but not committed: {only_fresh}")
            if only_committed:
                diffs.append(f"anchors: present in committed but not a fresh generate: {only_committed}")
            if changed:
                diffs.append(f"anchors: fields differ for id(s): {changed}")
        else:
            diffs.append(f"{key}: differs")
    return diffs


def cmd_check(args) -> int:
    # Exit-code reconciliation (T013/T014 review finding Important-1, fixed
    # 2026-09-26): contracts/generator-cli.md's own exit-code table reserves
    # code 1 for "Drift detected (check mode only)" and code 4 SEPARATELY
    # for "Hand-edit divergence detected (check mode, G-004)" — the original
    # implementation returned 1 for every divergence branch, leaving code 4
    # permanently unreachable dead specification. The two conditions ARE
    # genuinely distinguishable, not a redundant contract-authoring
    # artifact: comparing the SOURCE's own content hash (see
    # _source_content_hash — a git-commit-based first attempt at this same
    # comparison was tried and found genuinely broken, both for a --source
    # outside any git repo AND, latently, for one inside a repo where an
    # UNRELATED commit could move HEAD without touching the source file's
    # own bytes) against the committed index's own recorded hash tells
    # whether the source's CONTENT moved since the last `generate`
    # (ordinary staleness/DRIFT, exit 1 — the expected, benign state while
    # Constitution.md is being actively edited) or stayed byte-identical
    # while the COMMITTED OUTPUT itself diverges from what `generate` would
    # currently produce (a genuine HAND-EDIT/tamper signal per G-004,
    # exit 4 — the source is unchanged, so nothing legitimate explains the
    # divergence). This is a real, actionable distinction this project's
    # own governance discipline treats as first-class (tamper-evidence vs.
    # ordinary staleness), not merely a cosmetic exit-code split.
    records = build_records(args.source)
    with __import__("tempfile").TemporaryDirectory() as tmp:
        fresh_groups_dir = os.path.join(tmp, "groups")
        fresh_index_out = os.path.join(tmp, "index.yaml")
        group_counts = write_groups(records, fresh_groups_dir)
        fresh_index = build_yaml_index(records, group_counts, args.source, fresh_index_out)

        if not os.path.exists(args.index_out):
            sys.stderr.write(f"FATAL: {args.index_out} does not exist — run 'generate' first\n")
            return 1
        with open(args.index_out) as f:
            committed_index = yaml.safe_load(f)

        source_hash = fresh_index["generated_from"]["source_sha256"]
        committed_hash = committed_index.get("generated_from", {}).get("source_sha256")
        # source_hash == committed_hash (source content byte-identical since
        # the last generate) => any divergence found below is a hand-edit of
        # the OUTPUT (G-004, exit 4). Otherwise the source itself changed,
        # so a divergence is ordinary drift/staleness (exit 1). A committed
        # index from BEFORE this field existed has no source_sha256 at all
        # (None != any real hash), so an old committed index is correctly
        # treated as "source changed" (exit 1, the safe/conservative
        # default) rather than silently assumed unchanged.
        divergence_exit_code = 4 if source_hash == committed_hash else 1

        if _content_hash(fresh_index) != _content_hash(committed_index):
            diffs = _diverged_index_fields(fresh_index, committed_index)
            sys.stderr.write(
                "FATAL: committed constitution_index.yaml diverges from a fresh generate "
                f"— diverged field(s): {diffs}\n"
            )
            return divergence_exit_code

        for group in group_counts:
            fresh_path = os.path.join(fresh_groups_dir, f"{group}.md")
            committed_path = os.path.join(args.groups_dir, f"{group}.md")
            if not os.path.exists(committed_path):
                sys.stderr.write(f"FATAL: {committed_path} missing (was 'generate' run?)\n")
                return divergence_exit_code
            with open(fresh_path) as f1, open(committed_path) as f2:
                if f1.read() != f2.read():
                    sys.stderr.write(
                        f"FATAL: constitution/groups/{group}.md diverges from a fresh "
                        f"generate — hand-edit or stale commit (FR-012)\n"
                    )
                    return divergence_exit_code
    print("check: no drift")
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("generate")
    sp.add_argument("--source", required=True)
    sp.add_argument("--groups-dir", required=True)
    sp.add_argument("--index-out", required=True)
    sp.set_defaults(func=cmd_generate)
    sp2 = sub.add_parser("check")
    sp2.add_argument("--source", required=True)
    sp2.add_argument("--groups-dir", required=True)
    sp2.add_argument("--index-out", required=True)
    sp2.set_defaults(func=cmd_check)
    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
