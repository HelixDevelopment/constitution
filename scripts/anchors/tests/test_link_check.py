# constitution/scripts/anchors/tests/test_link_check.py
import subprocess, tempfile, os, sys

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")
LINK_CHECK = os.path.join(os.path.dirname(__file__), "..", "constitution_link_check.py")


def test_selftest_control_needles_pass():
    # Uses a small, CONTROLLED synthetic corpus (a single-file tempdir citing
    # exactly one REAL anchor id) — not the real project corpus
    # (constitution/ + CLAUDE.md + AGENTS.md). Fixed 2026-09-26: the plan's
    # own literal test pointed --corpus directly at the real, messy project
    # corpus and asserted `returncode == 0` — but the checker (correctly,
    # per its own L-005 "NEVER exits 0 while any UNRESOLVED citation
    # exists") found FOUR genuine, PRE-EXISTING dangling citations there
    # (§11.4.205/§11.4.206 — cited across ALL FIVE lockstep-mirror files as
    # if canonically defined, yet with NO heading-form definition anywhere
    # in constitution/Constitution.md; §11.4.64 similarly never
    # independently defined; §11.4.175 cited only from an explicit
    # in-progress `drafts/` file), none of which this feature's T021/T022
    # link-checker task exists to fix (filed as a tracked follow-up item
    # instead, per §11.4.197 — see evidence/link_check_real_corpus_scan.txt
    # + the filed tracker id). A CI-gating unit test asserting a full
    # real-corpus scan resolves cleanly would make this test permanently
    # RED for a pre-existing content gap this feature does not own,
    # conflating "the INSTRUMENT is trustworthy" (this test's actual job,
    # per L-002/L-003) with "the WHOLE PROJECT'S existing prose has zero
    # dangling citations" (a much stronger, unrelated claim). This test
    # asserts only the former, decoupled from the real corpus's ever-
    # evolving content state; the latter is honestly captured once, as
    # evidence, in a separate real-corpus run (see T024's review package).
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)

        # A single clean fixture file citing ONE real, known-resolvable
        # anchor id (§11.4.230, the same standing positive-control fixture
        # T018/T019/T020 already use — reused deliberately, not a new
        # guess) plus, deliberately, NOTHING else — so this scan's own
        # PASS is unconditional on the real corpus's independent content.
        clean_corpus_dir = os.path.join(tmp, "clean_corpus")
        os.makedirs(clean_corpus_dir)
        with open(os.path.join(clean_corpus_dir, "sample.md"), "w") as f:
            f.write("See §11.4.230 for the parallelized-pipeline methodology.\n")

        r = subprocess.run(
            ["python3", LINK_CHECK, "--index", index_out, "--corpus",
             clean_corpus_dir, "--selftest"],
            capture_output=True, text=True,
        )
        assert r.returncode == 0, r.stdout + r.stderr
        assert "positive control resolved" in r.stdout
        assert "negative control correctly unresolved" in r.stdout
        assert "all citations resolved" in r.stdout


def test_negative_control_flags_fabricated_citation_in_a_real_scan():
    # Complements the selftest above: proves the checker's FULL-SCAN path
    # (not just --selftest's internal fixture check) genuinely reports a
    # deliberately-fabricated citation as UNRESOLVED with a non-zero exit,
    # against a controlled corpus containing exactly one bad citation.
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)

        bad_corpus_dir = os.path.join(tmp, "bad_corpus")
        os.makedirs(bad_corpus_dir)
        with open(os.path.join(bad_corpus_dir, "sample.md"), "w") as f:
            f.write("See §11.4.99999 for a citation that does not exist.\n")

        r = subprocess.run(
            ["python3", LINK_CHECK, "--index", index_out, "--corpus", bad_corpus_dir],
            capture_output=True, text=True,
        )
        assert r.returncode == 1, r.stdout + r.stderr
        assert "UNRESOLVED: §11.4.99999" in r.stdout
        assert "1 unresolved citation(s)" in r.stdout


def test_parenthesized_suffix_distinct_sub_anchor_not_silently_truncated():
    # T024 independent review finding (IMPORTANT, 2026-09-26): before this
    # fix, CITATION_RE's character class stopped BEFORE any parenthesized
    # suffix, so `§11.4.184(I)` was captured as bare `11.4.184` and silently
    # resolved against the WRONG anchor — `11.4.184` and `11.4.184(I)` are
    # two distinct, separately-defined, real headings in this corpus
    # (confirmed live via extract_anchors()). This test proves BOTH
    # directions: a genuine distinct parenthesized-suffix sub-anchor
    # resolves to ITSELF (never silently truncated to its unrelated
    # numeric-prefix neighbour), and a genuine parenthesized CLAUSE
    # reference (§11.4.4(b), which has no anchor of its own) still resolves
    # via L-004's parent-stripping fallback.
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from constitution_link_check import CITATION_RE, _resolve

    known_ids = {"11.4.184", "11.4.184(I)", "11.4.4"}  # 11.4.4(b) deliberately absent

    m = CITATION_RE.search("§11.4.184(I)")
    assert m and m.group(1) == "11.4.184(I)", f"citation regex mis-captured: {m}"
    assert _resolve(m.group(1), known_ids) is True
    # The defect this test guards against: resolving via the WRONG anchor
    # (truncating to the bare parent) would ALSO return True here since
    # "11.4.184" is in known_ids — so the real proof is that the captured
    # id itself was NOT truncated before resolution (checked above), not
    # merely that _resolve() returns True.

    m2 = CITATION_RE.search("§11.4.4(b)")
    assert m2 and m2.group(1) == "11.4.4(b)"
    assert _resolve(m2.group(1), known_ids) is True, (
        "a genuine clause-reference (no anchor of its own) must still "
        "resolve via parent-stripping"
    )


def test_unresolved_citation_names_a_real_line_number_never_capped_at_50():
    # Final whole-branch review finding I-3, 2026-09-26, IMPORTANT: the
    # checker's own contract (L-001/L-005) requires "naming every
    # UNRESOLVED citation by file:line" — the prior implementation carried
    # no line number at all, and truncated its printed findings to the
    # first 50 regardless of how many real citations were actually
    # unresolved (the real corpus has 288; 240 -- 83% -- were silently
    # unprinted before this fix). This test proves BOTH halves: a
    # fabricated citation on a KNOWN line number is reported with that
    # EXACT line number, and MORE than 50 fabricated citations are ALL
    # reported (never truncated).
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)

        bad_corpus_dir = os.path.join(tmp, "bad_corpus_many")
        os.makedirs(bad_corpus_dir)
        # 60 fabricated citations, one per line, each on a KNOWN line
        # number (1-indexed) -- more than the old cap of 50.
        with open(os.path.join(bad_corpus_dir, "sample.md"), "w") as f:
            for i in range(60):
                f.write(f"line {i}: see §11.4.9999{i} for detail.\n")

        r = subprocess.run(
            ["python3", LINK_CHECK, "--index", index_out, "--corpus", bad_corpus_dir],
            capture_output=True, text=True,
        )
        assert r.returncode == 1, r.stdout + r.stderr
        assert "60 unresolved citation(s)" in r.stdout, (
            f"expected all 60 fabricated citations reported (no 50-cap truncation), "
            f"got: {r.stdout}"
        )
        # Line 1 (1-indexed) carries §11.4.99990 -- assert its EXACT reported line number.
        assert "§11.4.99990 in " in r.stdout and ":1\n" in r.stdout.split("§11.4.99990 in ")[1][:80], (
            f"the first fabricated citation's line number was not reported correctly: {r.stdout}"
        )
        # Line 60 carries §11.4.999959 -- assert its line number too, at the other end.
        assert "§11.4.999959 in " in r.stdout and ":60\n" in r.stdout.split("§11.4.999959 in ")[1][:80], (
            f"the last fabricated citation's line number was not reported correctly: {r.stdout}"
        )


if __name__ == "__main__":
    test_selftest_control_needles_pass()
    test_negative_control_flags_fabricated_citation_in_a_real_scan()
    test_parenthesized_suffix_distinct_sub_anchor_not_silently_truncated()
    test_unresolved_citation_names_a_real_line_number_never_capped_at_50()
    print("PASS")
