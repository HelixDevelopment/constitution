# constitution/scripts/anchors/tests/test_wiring_audit_us4.py
import subprocess, tempfile, os, sys, yaml

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

def test_genuine_gap_classification_and_non_code_evidence_rejected():
    # T024 independent review finding (CRITICAL, 2026-09-26): before this
    # fix, ANY textual mention of a gate name outside the 5 excluded .md
    # basenames counted as "IMPLEMENTED" (measured live: 123/166 = 74% of
    # the real report's own "IMPLEMENTED" evidence was `.tsv` data-pack
    # ledgers, 7 were `.html` doc-twin exports, 3 were `.txt` — only 33
    # (20%) were genuine `.sh` gate scripts), making the checker
    # STRUCTURALLY INCAPABLE of ever reporting a gap against a corpus whose
    # own separately-measured §11.4.227 anchor states "241/413 = 58%
    # unimplemented." No test in this suite ever exercised the
    # NAMED-BUT-UNIMPLEMENTED classification path at all
    # (`grep -rn "NAMED-BUT-UNIMPLEMENTED" tests/` returned zero hits) —
    # this test closes that gap with a constructed fixture proving BOTH
    # halves: (a) a gate name mentioned ONLY in a non-code file (.tsv) is
    # correctly classified as a gap, NOT accepted as evidence; (b) a gate
    # name mentioned in a real .sh file IS correctly classified as
    # implemented.
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    import constitution_wiring_audit as cwa

    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "gates"))
        # A gate mentioned ONLY in a non-code ledger — must NOT count as evidence.
        with open(os.path.join(tmp, "gates", "ledger.tsv"), "w") as f:
            f.write("CM-FIXTURE-GAP-ONLY\tsome-anchor\tstatus\n")
        # A gate mentioned in a genuine executable gate script — MUST count.
        with open(os.path.join(tmp, "gates", "cm_fixture_wired.sh"), "w") as f:
            f.write("#!/usr/bin/env bash\n# implements CM-FIXTURE-WIRED\nexit 0\n")

        gate_names = {"CM-FIXTURE-GAP-ONLY", "CM-FIXTURE-WIRED"}
        gate_index = cwa._build_gate_index(tmp, gate_names)

        gap_anchor = {"id": "99.9.1", "propagation_gate": "CM-FIXTURE-GAP-ONLY"}
        wired_anchor = {"id": "99.9.2", "propagation_gate": "CM-FIXTURE-WIRED"}

        gap_status, gap_hits = cwa._classify_anchor(gap_anchor, gate_index)
        wired_status, wired_hits = cwa._classify_anchor(wired_anchor, gate_index)

        assert gap_status == "NAMED-BUT-UNIMPLEMENTED", (
            f"a gate mentioned ONLY in a .tsv ledger was wrongly classified "
            f"'{gap_status}' — non-code evidence is being accepted again"
        )
        assert gap_hits == [], f"a gap classification must carry no evidence: {gap_hits}"
        assert wired_status == "IMPLEMENTED", (
            f"a gate genuinely implemented in a real .sh file was wrongly "
            f"classified '{wired_status}'"
        )
        assert wired_hits and wired_hits[0].endswith("cm_fixture_wired.sh")


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
    test_genuine_gap_classification_and_non_code_evidence_rejected()
    test_selftest_failure_refuses_to_write_report()
    print("PASS")
