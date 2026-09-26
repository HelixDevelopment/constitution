# constitution/scripts/anchors/tests/test_link_check.py
import subprocess, tempfile, os

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


if __name__ == "__main__":
    test_selftest_control_needles_pass()
    test_negative_control_flags_fabricated_citation_in_a_real_scan()
    print("PASS")
