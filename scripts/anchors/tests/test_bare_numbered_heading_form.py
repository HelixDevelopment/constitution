"""Bare numbered-heading anchor form (`### N.M Title`, no `§`).

Real-corpus defect this file guards (2026-10-08): constitution/Constitution.md
defines two genuine anchors with a bare numbered `###` heading and NO `§`
sign — `### 1.1 False-positive immunity is an invariant` and
`### 2.1 Multi-upstream push is the norm` — both cited throughout the corpus
as `§1.1` / `§2.1` (§1.1 alone ~280 times). anchor_lib only recognised the
`### §N.N` form, so both were silently absent from constitution_index.yaml,
and every consumer resolving a `§1.1` citation against the index went blind
on it.

The fixtures pin BOTH directions (§11.4.201(1)): the bare form opens an
anchor, AND body text / list items / version numbers / other heading levels
that merely LOOK numbered never do. The real-file test is an independent
oracle (it does not call anchor_lib) over the real Constitution.md, with a
positive and a negative control needle (§11.4.273).
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from anchor_lib import (  # noqa: E402
    extract_anchors, MalformedHeadingError, assign_group,
)

CONSTITUTION_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CORPUS = os.path.join(CONSTITUTION_ROOT, "Constitution.md")
INDEX = os.path.join(CONSTITUTION_ROOT, "constitution_index.yaml")


def test_bare_numbered_heading_opens_an_anchor():
    src = (
        "## 1. Test coverage\n"
        "intro\n"
        "### 1.1 False-positive immunity is an invariant\n"
        "body one\n"
        "## 2. Commit mechanics\n"
        "### 2.1 Multi-upstream push is the norm\n"
        "body two\n"
        "### §11.4.1 — Hash form\n"
        "body three\n"
    )
    anchors = extract_anchors(src)
    assert [a["id"] for a in anchors] == ["1.1", "2.1", "11.4.1"], [a["id"] for a in anchors]
    assert anchors[0]["title"] == "False-positive immunity is an invariant"
    assert anchors[1]["title"] == "Multi-upstream push is the norm"
    assert "body one" in anchors[0]["body"]
    assert "body two" not in anchors[0]["body"]
    assert "body two" in anchors[1]["body"]
    assert "body three" not in anchors[1]["body"]


def test_bare_form_does_not_depend_on_a_parent_section_heading():
    # A regrouped document (constitution/groups/*.md, governance_subset)
    # carries the anchor WITHOUT its original `## N.` parent — the anchor
    # must still be recognised there, or a re-parse silently drops it.
    src = "# Some Group\n\n### 1.1 False-positive immunity is an invariant\nbody\n"
    assert [a["id"] for a in extract_anchors(src)] == ["1.1"]


def test_lookalikes_never_open_an_anchor():
    src = (
        "### §11.4.1 — Real anchor\n"
        "7.1 audio channels are captured with tinycap\n"     # body text
        "1.1 is cited everywhere as the mutation rule\n"     # body text
        "- 1.1 item in a bullet list\n"                      # list item
        "1. 1.1 numbered list step\n"                        # ordered list
        "  ### 1.1 indented is not a heading\n"              # not at col 0
        "### 1.2.3 Release notes\n"                          # 3-part version
        "### 1.2.0 Release\n"                                # 3-part version
        "### v1.2 Release\n"                                 # v-prefixed version
        "#### 1.1 Deeper heading level\n"                    # wrong level
        "## 1.1 Shallower heading level\n"                   # wrong level
        "##### 2.1 Deeper still\n"
        "tail\n"
    )
    anchors = extract_anchors(src)
    assert [a["id"] for a in anchors] == ["11.4.1"], [a["id"] for a in anchors]
    assert "tail" in anchors[0]["body"]
    assert "7.1 audio" in anchors[0]["body"]


def test_attempted_bare_opener_without_a_title_fails_loud():
    for bad in ("### 1.1\n", "### 1.1 \n", "### 1.1:Title\n", "### 1.1x Title\n"):
        try:
            extract_anchors(bad)
        except MalformedHeadingError:
            continue
        raise AssertionError(f"expected MalformedHeadingError for {bad!r}")


def test_bare_ids_and_276_classify_into_a_group():
    for aid in ("1.1", "2.1", "11.4.276"):
        assign_group(aid)  # raises UnclassifiedAnchorError if unmapped


# ---------------------------------------------------------------------------
# Real-file oracle — independent of anchor_lib (producer != verifier).
# ---------------------------------------------------------------------------
_HEADING_ID_RE = re.compile(
    r'^#{2,3} §?(\d+\.\d+(?:\.\d+)?(?:\.[A-Z]|\([A-Z]+\))?)(?=[ \t])')


def _real_heading_ids_cited_as_anchors(text):
    lines = text.splitlines()
    heading_ids = {}
    for n, line in enumerate(lines, 1):
        m = _HEADING_ID_RE.match(line)
        if m:
            heading_ids.setdefault(m.group(1), n)
    cited = set()
    for aid, n in heading_ids.items():
        pat = re.compile(r'§' + re.escape(aid) + r'(?![\d])')
        for m_n, line in enumerate(lines, 1):
            if m_n != n and pat.search(line):
                cited.add(aid)
                break
    return heading_ids, cited


def _index_ids_and_sha():
    import yaml
    with open(INDEX, encoding="utf-8") as f:
        idx = yaml.safe_load(f)
    return {a["id"] for a in idx["anchors"]}, idx["generated_from"]["source_sha256"]


def test_every_cited_numbered_heading_in_the_real_corpus_is_indexed():
    with open(CORPUS, encoding="utf-8") as f:
        text = f.read()
    heading_ids, cited = _real_heading_ids_cited_as_anchors(text)
    index_ids, index_sha = _index_ids_and_sha()

    # Control needles (§11.4.273): the oracle can SEE a known heading and a
    # known bare heading, and does NOT see a fabricated one.
    assert "11.4.209" in cited, "oracle blind: positive needle 11.4.209 not found"
    assert "1.1" in heading_ids, "oracle blind: bare-form needle 1.1 not found"
    assert "11.4.999" not in heading_ids, "oracle over-broad: negative needle matched"
    assert len(cited) > 250, f"oracle blind-ish: only {len(cited)} cited headings"
    # Index control needles: the index loader sees a real id, not a fake one.
    assert "11.4.209" in index_ids and "11.4.999" not in index_ids

    missing = sorted(cited - index_ids)
    assert not missing, f"cited numbered headings absent from the index: {missing}"

    # Freshness: the index must have been generated from THESE bytes.
    with open(CORPUS, "rb") as f:
        live_sha = hashlib.sha256(f.read()).hexdigest()
    assert index_sha == live_sha, (
        f"constitution_index.yaml is stale: generated from {index_sha[:12]}, "
        f"corpus is {live_sha[:12]}")


def test_parser_agrees_with_the_oracle_on_the_real_corpus():
    with open(CORPUS, encoding="utf-8") as f:
        text = f.read()
    heading_ids, cited = _real_heading_ids_cited_as_anchors(text)
    parsed = {a["id"] for a in extract_anchors(text)}
    missing = sorted(cited - parsed)
    assert not missing, f"parser misses cited numbered headings: {missing}"
    assert {"1.1", "2.1", "11.4.276"} <= parsed


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
