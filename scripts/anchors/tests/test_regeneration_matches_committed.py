"""Committed index + groups == a fresh regeneration; anchor-body boundary pinned as a KNOWN LIMITATION.

R3-08 (round-3 review, 2026-10-08): no test compared the generator's output with the committed
constitution_index.yaml and groups/*.md, so a change to the generator that moved an anchor to a
different group (reviewer mutation G5: `"1.1": "testing-and-tdd"` -> `"git-and-data-safety"`) still
passed the whole suite. This file runs the REAL generator (`constitution_generate.py generate`, its
real CLI) into a temporary directory and compares every output byte-for-byte with the committed
files. Only `generated_at` and `generated_from.commit` are excluded: both are provenance metadata
that the generator's own `check` mode also excludes (a fresh run has a new timestamp; `commit` is the
HEAD of the source directory at generate time).

The comparator is proven able to fail (§11.4.273): the reviewer's G5 mutation is applied to a COPY of
anchor_lib.py, that copy's generator is run, and the comparison must report the moved anchor.

R3-01 (round-3 review): an anchor body runs until the NEXT ANCHOR OPENER, not until a higher-level
`##`/`#` section heading, so `### 2.1` absorbs the whole of sections 3-7 of Constitution.md. Changing
that rule is a generator-wide governance decision tracked as ATM-1130 (it re-cuts existing bodies such
as 9.4 and changes derived metadata), so it is NOT changed here. The current behaviour is pinned below
as an explicit KNOWN LIMITATION, so that the ATM-1130 fix shows up as a visible, deliberate edit of
these assertions rather than a silent change.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ANCHORS = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, ANCHORS)
from anchor_lib import extract_anchors  # noqa: E402

CONSTITUTION_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CORPUS = os.path.join(CONSTITUTION_ROOT, "Constitution.md")
INDEX = os.path.join(CONSTITUTION_ROOT, "constitution_index.yaml")
GROUPS = os.path.join(CONSTITUTION_ROOT, "groups")

# Provenance lines excluded from the index comparison (and nothing else).
_PROVENANCE_RE = re.compile(r"^(generated_at: |  commit: )")


def _index_lines(path):
    with open(path, encoding="utf-8") as fh:
        return [l for l in fh.read().split("\n") if not _PROVENANCE_RE.match(l)]


def _md_files(d):
    return sorted(f for f in os.listdir(d) if f.endswith(".md"))


def compare(groups_a, index_a, groups_b, index_b):
    """Differences between two (groups dir, index file) outputs, as human-readable strings."""
    diffs = []
    names_a, names_b = _md_files(groups_a), _md_files(groups_b)
    if names_a != names_b:
        diffs.append("group file sets differ: %s vs %s" % (names_a, names_b))
    for n in sorted(set(names_a) & set(names_b)):
        with open(os.path.join(groups_a, n), "rb") as fa, open(os.path.join(groups_b, n), "rb") as fb:
            if fa.read() != fb.read():
                diffs.append("groups/%s differs" % n)
    la, lb = _index_lines(index_a), _index_lines(index_b)
    if la != lb:
        first = next((i for i, (x, y) in enumerate(zip(la, lb)) if x != y), min(len(la), len(lb)))
        diffs.append("constitution_index.yaml differs from line %d: %r vs %r"
                     % (first + 1, la[first] if first < len(la) else None, lb[first] if first < len(lb) else None))
    return diffs


def _generate(anchors_dir, out_dir):
    groups = os.path.join(out_dir, "groups")
    index = os.path.join(out_dir, "constitution_index.yaml")
    p = subprocess.run([sys.executable, os.path.join(anchors_dir, "constitution_generate.py"), "generate",
                        "--source", CORPUS, "--groups-dir", groups, "--index-out", index],
                       capture_output=True, text=True, timeout=300)
    assert p.returncode == 0, "generate exited %d: %s" % (p.returncode, p.stderr[-800:])
    return groups, index


def test_committed_output_equals_a_fresh_regeneration():
    tmp = tempfile.mkdtemp()
    try:
        groups, index = _generate(ANCHORS, tmp)
        # Control needle: the regenerated output is not empty and carries a known anchor.
        assert _md_files(groups), "the generator wrote no group file -- the comparison would be vacuous"
        with open(index, encoding="utf-8") as fh:
            assert re.search(r"(?m)^- id: '?11\.4\.108'?$", fh.read()), "control needle 11.4.108 absent from the regenerated index"
        diffs = compare(GROUPS, INDEX, groups, index)
        assert not diffs, "committed index/groups differ from a fresh regeneration: %s" % diffs
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_comparator_catches_a_changed_byte():
    tmp = tempfile.mkdtemp()
    try:
        groups, index = _generate(ANCHORS, tmp)
        victim = os.path.join(groups, _md_files(groups)[0])
        with open(victim, "ab") as fh:
            fh.write(b"x")
        diffs = compare(GROUPS, INDEX, groups, index)
        assert any(os.path.basename(victim) in d for d in diffs), diffs
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_g5_moving_an_anchor_between_groups_is_caught():
    """The round-3 reviewer's G5 mutation, adopted: 1.1 moved to git-and-data-safety."""
    tmp = tempfile.mkdtemp()
    try:
        mut = os.path.join(tmp, "anchors")
        shutil.copytree(ANCHORS, mut, ignore=shutil.ignore_patterns("__pycache__", "tests"))
        lib = os.path.join(mut, "anchor_lib.py")
        with open(lib, encoding="utf-8") as fh:
            text = fh.read()
        target = '"1.1": "testing-and-tdd",'
        assert text.count(target) == 1, "G5 target occurs %d times" % text.count(target)
        with open(lib, "w", encoding="utf-8") as fh:
            fh.write(text.replace(target, '"1.1": "git-and-data-safety",'))
        groups, index = _generate(mut, os.path.join(tmp, "out"))
        diffs = compare(GROUPS, INDEX, groups, index)
        assert any("git-and-data-safety.md" in d for d in diffs) and any("testing-and-tdd.md" in d for d in diffs), diffs
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_known_limitation_atm_1130_anchor_body_crosses_section_headings():
    """KNOWN LIMITATION (ATM-1130): an anchor body is closed only by the next anchor opener, so a
    higher-level `## N.` section heading and its text are absorbed into the previous anchor's body.
    When ATM-1130 changes the boundary rule, these assertions MUST be inverted in the same change."""
    src = (
        "## 1. Test coverage\n"
        "### 1.1 False-positive immunity is an invariant\n"
        "body one\n"
        "## 2. Commit mechanics\n"
        "section two text\n"
        "### 2.1 Multi-upstream push is the norm\n"
        "body two\n"
    )
    a = {x["id"]: x for x in extract_anchors(src)}
    assert "## 2. Commit mechanics" in a["1.1"]["body"], \
        "ATM-1130 boundary behaviour changed: update this KNOWN-LIMITATION test deliberately"
    assert "section two text" in a["1.1"]["body"]
    assert "body two" not in a["1.1"]["body"]


def test_known_limitation_atm_1130_real_corpus_2_1_absorbs_sections_3_to_7():
    """The same limitation on the real Constitution.md: anchor 2.1's body contains the `## 3.` to
    `## 7.` section headings (R3-01). Control needle: the `## 3.` heading exists in the corpus."""
    with open(CORPUS, encoding="utf-8") as fh:
        text = fh.read()
    heads = re.findall(r"(?m)^## [3-7]\. .*$", text)
    assert len(heads) == 5, "control needle: expected the five `## 3.`-`## 7.` headings, found %s" % heads
    body = {x["id"]: x for x in extract_anchors(text)}["2.1"]["body"]
    for h in heads:
        assert h in body, "ATM-1130 boundary behaviour changed (%r no longer in 2.1's body): " \
                          "update this KNOWN-LIMITATION test deliberately" % h


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL {t.__name__}: {type(e).__name__}: {e}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)
