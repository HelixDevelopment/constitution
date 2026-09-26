# constitution/scripts/anchors/tests/test_generate_us3.py
import subprocess, tempfile, os, shutil

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")

def _run(args):
    return subprocess.run(["python3", GEN] + args, capture_output=True, text=True)

def test_determinism_two_check_runs_agree():
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        r1 = _run(["generate", "--source", "constitution/Constitution.md",
                    "--groups-dir", groups_dir, "--index-out", index_out])
        assert r1.returncode == 0, r1.stderr
        c1 = _run(["check", "--source", "constitution/Constitution.md",
                    "--groups-dir", groups_dir, "--index-out", index_out])
        c2 = _run(["check", "--source", "constitution/Constitution.md",
                    "--groups-dir", groups_dir, "--index-out", index_out])
        assert c1.returncode == 0, c1.stderr
        assert c2.returncode == 0, c2.stderr

def test_malformed_heading_exits_2_no_partial_output():
    with tempfile.TemporaryDirectory() as tmp:
        broken = os.path.join(tmp, "broken.md")
        with open("constitution/Constitution.md") as f:
            text = f.read()
        broken_text = text.replace("### §11.4.209 ", "### §11.4.209(broken ", 1)
        with open(broken, "w") as f:
            f.write(broken_text)
        groups_dir = os.path.join(tmp, "out_groups")
        r = _run(["generate", "--source", broken,
                   "--groups-dir", groups_dir, "--index-out", os.path.join(tmp, "out_index.yaml")])
        assert r.returncode == 2, r.stdout + r.stderr
        assert not os.path.isdir(groups_dir) or not os.listdir(groups_dir), \
            "no partial output allowed on fail-loud exit"

def test_no_partial_output_when_write_fails_after_groups_already_written():
    # New test (2026-09-26, T013/T014 review remediation — Minor finding):
    # test_malformed_heading_exits_2_no_partial_output above does NOT
    # actually exercise the scratch-then-rename guard — build_records's own
    # sys.exit(2) fires before write_groups is ever called, so that test
    # would still pass even with the whole scratch/rename mechanism fully
    # reverted (independently confirmed by the review, and reproducible: a
    # revert of cmd_generate to its pre-T014 direct-write body leaves that
    # test green). This test injects a fault AFTER write_groups has ALREADY
    # written real content into the scratch directory, but BEFORE the
    # scratch-to-real rename ever runs — an invalid --index-out path (a
    # nonexistent parent directory `open()` cannot auto-create) makes
    # build_yaml_index's write crash with an uncaught OSError, proving the
    # REAL --groups-dir is genuinely never populated even though the
    # scratch write it would have been renamed FROM did succeed.
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")  # deliberately never created ahead of time
        bad_index_out = os.path.join(tmp, "no_such_subdir", "index.yaml")
        r = _run(["generate", "--source", "constitution/Constitution.md",
                   "--groups-dir", groups_dir, "--index-out", bad_index_out])
        assert r.returncode != 0, "an invalid --index-out path MUST fail, not silently succeed"
        assert not os.path.isdir(groups_dir), (
            "the REAL --groups-dir MUST stay untouched when the write fails "
            "AFTER write_groups already succeeded but BEFORE the scratch-to-"
            "real rename — this is the property the scratch-then-rename "
            "guard exists to prove, and this test genuinely reaches it "
            "(unlike the malformed-heading test above, which fails before "
            "write_groups is ever called)"
        )
        # Control needle (§11.4.201/§11.4.273): confirm the scratch write
        # DID actually succeed before the crash — otherwise this test would
        # trivially pass for the WRONG reason (nothing was ever written at
        # all, rather than something real being written-then-discarded).
        scratch_dir = groups_dir + ".scratch"
        assert os.path.isdir(scratch_dir) and os.listdir(scratch_dir), (
            "control needle failed: the scratch directory itself was never "
            "populated, so this test would not distinguish a working guard "
            "from a write_groups that never ran at all"
        )

def test_hand_edit_to_grouped_doc_detected_as_drift():
    # Exit-code corrected 2026-09-26 (T013/T014 review finding Important-1):
    # cmd_check now distinguishes "source unchanged, output hand-edited"
    # (this test's own exact scenario — the source file never changes
    # between the initial generate and the later check call) from ordinary
    # source-drift/staleness, per contracts/generator-cli.md's own
    # exit-code table (4 = "Hand-edit divergence detected (check mode,
    # G-004)", previously unreachable dead specification — see
    # test_check_reports_ordinary_drift_as_exit_1_when_source_itself_
    # changed below for the DISTINCT exit-1 case, proving this is a real
    # two-way distinction and not merely a renumbering).
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        _run(["generate", "--source", "constitution/Constitution.md",
              "--groups-dir", groups_dir, "--index-out", index_out])
        # Corrupt one grouped document by hand — this is the FR-012 paired mutation.
        target = next(f for f in os.listdir(groups_dir) if f.endswith(".md"))
        with open(os.path.join(groups_dir, target), "a") as f:
            f.write("\nHAND-EDITED LINE THAT MUST BE DETECTED AS DRIFT\n")
        r = _run(["check", "--source", "constitution/Constitution.md",
                   "--groups-dir", groups_dir, "--index-out", index_out])
        assert r.returncode == 4, (
            f"hand-edit with an UNCHANGED source MUST be detected as G-004 "
            f"hand-edit-divergence (exit 4, not the general drift code 1) — "
            f"got {r.returncode}: {r.stderr}"
        )

def test_check_reports_ordinary_drift_as_exit_1_when_source_itself_changed():
    # New test (2026-09-26, T013/T014 review remediation): proves the OTHER
    # side of the exit-1-vs-exit-4 distinction cmd_check now makes — when
    # the SOURCE has genuinely moved on since the committed output was
    # generated (no hand-edit of the output at all), a resulting divergence
    # is ordinary staleness/drift (exit 1), never the G-004 hand-edit code.
    # A synthetic source (never the real constitution/Constitution.md) is
    # used so this test can genuinely mutate --source between the two
    # generate/check calls without touching any real corpus file.
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "synthetic.md")
        with open(src, "w") as f:
            f.write("### §11.4.206 — A synthetic anchor for drift-detection oracle testing\n\n"
                     "Classification: universal\n\n")
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        r_gen = _run(["generate", "--source", src, "--groups-dir", groups_dir, "--index-out", index_out])
        assert r_gen.returncode == 0, r_gen.stderr
        # Change the SOURCE itself (not the committed output) — a genuine
        # content edit, so the source's own new content differs from what
        # was generated, without ever touching groups_dir/index_out by hand.
        with open(src, "a") as f:
            f.write("### §12.7 — A second synthetic anchor added after the first generate\n\n"
                     "Classification: universal\n\n")
        r_check = _run(["check", "--source", src, "--groups-dir", groups_dir, "--index-out", index_out])
        assert r_check.returncode == 1, (
            f"a genuinely-changed source MUST be reported as ordinary drift "
            f"(exit 1), never the G-004 hand-edit code — got {r_check.returncode}: {r_check.stderr}"
        )

if __name__ == "__main__":
    test_determinism_two_check_runs_agree()
    test_malformed_heading_exits_2_no_partial_output()
    test_no_partial_output_when_write_fails_after_groups_already_written()
    test_hand_edit_to_grouped_doc_detected_as_drift()
    test_check_reports_ordinary_drift_as_exit_1_when_source_itself_changed()
    print("PASS")
