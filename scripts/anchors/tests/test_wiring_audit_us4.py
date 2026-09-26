# constitution/scripts/anchors/tests/test_wiring_audit_us4.py
import subprocess, tempfile, os, yaml

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")
AUDIT = os.path.join(os.path.dirname(__file__), "..", "constitution_wiring_audit.py")

def test_control_needles_pass_selftest():
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)
        report = os.path.join(tmp, "wiring_gap_report.md")
        r = subprocess.run(["python3", AUDIT, "--index", index_out, "--consumer-root", ".",
                             "--report", report, "--selftest"],
                            capture_output=True, text=True)
        assert r.returncode == 0, r.stdout + r.stderr
        with open(report) as f:
            text = f.read()
        assert "11.4.230" in text  # W-003 positive control: NOT flagged as a gap
        # confirm it's not in a "gap" section specifically.
        # Fixed 2026-09-26: the plan's own literal `text.split("## Gaps")[-1]`
        # captures EVERYTHING from "## Gaps" to end-of-file, which INCLUDES
        # the later "## Implemented" section — so a genuinely-implemented
        # anchor (correctly listed under "## Implemented", which the real
        # report always places AFTER "## Gaps") was being counted as if it
        # were inside the gap section, making this assertion fail even when
        # the checker classified everything correctly. Confirmed via direct
        # reproduction: the report's real section order is Known-Pre-
        # Existing-Drift -> Gaps -> Implemented, and §11.4.230 genuinely (and
        # correctly) appears only in Implemented. Bounded the slice to stop
        # at the NEXT section header, matching the same two-way-split
        # pattern T020's own spot-check script already uses correctly
        # (`report_text.split("## Gaps")[1].split("## Implemented")[0]`).
        gap_section = (
            text.split("## Gaps")[-1].split("## Implemented")[0]
            if "## Gaps" in text else ""
        )
        assert "11.4.230" not in gap_section, "known-wired anchor was wrongly flagged"
        assert "11.4.108" in text  # W-004 negative control: IS a known, expected finding
        assert "ATM-1036" in text  # W-006: labeled distinct from a generic wiring gap

def test_selftest_failure_refuses_to_write_report():
    # Corrupt the corpus so the positive control CANNOT resolve, proving the
    # checker refuses to write an unproven report rather than bluffing (W-003).
    with tempfile.TemporaryDirectory() as tmp:
        empty_root = os.path.join(tmp, "empty_consumer_root")
        os.makedirs(empty_root)
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)
        report = os.path.join(tmp, "report.md")
        r = subprocess.run(["python3", AUDIT, "--index", index_out, "--consumer-root", empty_root,
                             "--report", report, "--selftest"],
                            capture_output=True, text=True)
        assert r.returncode == 1, "an empty consumer root cannot resolve §11.4.230 — MUST refuse"
        assert not os.path.exists(report), "no report written on a failed control-needle"

if __name__ == "__main__":
    test_control_needles_pass_selftest()
    test_selftest_failure_refuses_to_write_report()
    print("PASS")
