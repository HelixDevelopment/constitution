# constitution/scripts/anchors/tests/test_query_us2.py
import subprocess, tempfile, os, yaml

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")

def test_every_anchor_has_classification_and_explicit_gate_key():
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        r = subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                             "--groups-dir", groups_dir, "--index-out", index_out],
                            capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        with open(index_out) as f:
            idx = yaml.safe_load(f)
        assert idx["schema_version"] == 1
        for a in idx["anchors"]:
            # "mixed" added 2026-09-25 (census-validation finding): 2 real anchors
            # (§11.4.23, §11.4.24) carry this genuine third value — an enum check
            # that omits it would itself be wrong, not the generator.
            assert a["classification"] in ("universal", "project-specific", "mixed"), a["id"]
            assert "propagation_gate" in a, f"{a['id']} missing explicit propagation_gate key"

def test_filter_by_classification_matches_plain_yaml_list_comprehension():
    # US2's own Independent Test: a plain filter, no query engine, per
    # yaml-index-schema.md's Consumers section.
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)
        with open(index_out) as f:
            idx = yaml.safe_load(f)
        universal = [a for a in idx["anchors"] if a["classification"] == "universal"]
        project_specific = [a for a in idx["anchors"] if a["classification"] == "project-specific"]
        # "mixed" added 2026-09-25 (census-validation finding): a 2-way partition
        # assumption (universal + project-specific == total) is wrong once the
        # real 3rd enum value is correctly extracted — 2 real anchors (§11.4.23,
        # §11.4.24) would otherwise silently vanish from this sum, making it a
        # false negative on exactly the anchors this test exists to catch.
        mixed = [a for a in idx["anchors"] if a["classification"] == "mixed"]
        assert len(universal) + len(project_specific) + len(mixed) == len(idx["anchors"])
        assert len(universal) > 0  # this project's constitution is overwhelmingly universal-scoped
        assert len(mixed) == 2, f"expected exactly 2 mixed-classified anchors (§11.4.23, §11.4.24), got {len(mixed)}"

def test_project_specific_classification_is_detected_via_synthetic_fixture():
    # Correction (`/speckit-superspec-execute` proactive-audit finding D3,
    # 2026-09-25): the REAL constitution/Constitution.md corpus, verified
    # live, contains ZERO anchors ever classified `project-specific` (173
    # universal + 2 mixed = 175 Classification-shaped lines, 0 with a
    # `project-specific` value — confirmed via `grep -icE
    # 'Classification:\s*project-specific' Constitution.md` returning `0`,
    # AND via a full sweep of T017's own extraction regex tallying every
    # Classification value in the document). This is BY DESIGN of the
    # project's own §11.4.35 doctrine (project-specific rules live outside
    # the constitution submodule, only in a consuming project's own
    # governance files) — so `test_project_specific_count_matches_an_
    # independently_derived_manual_count` below, which cross-checks the
    # generator's count against an independent grep on the REAL corpus,
    # always compares `0 == 0` and can NEVER fail even if the
    # `project-specific`-detection code path were completely broken or
    # absent — there is no real positive data point to exercise it. This
    # test closes that gap with a SYNTHETIC fixture carrying a genuine
    # `project-specific`-classified anchor, so the extraction logic for
    # that specific value is actually exercised and can actually fail.
    with tempfile.TemporaryDirectory() as tmp:
        synthetic_src = os.path.join(tmp, "synthetic.md")
        # Ids corrected 2026-09-26 (controller-found T017 plan defect, pre-
        # existing and independent of the T010/T011 I-2 exit-code fix): the
        # plan's OWN literal fixture used ids "§99.1.1"/"§99.1.2", which fall
        # OUTSIDE every real-corpus id family (`assign_group` only classifies
        # the "11.4.*" numeric family plus a small fixed EXPLICIT_ID_GROUPS
        # set) -- so build_records's own assign_group call rejected them as
        # UnclassifiedAnchorError (exit 6) BEFORE the classification-metadata
        # extraction this test exists to exercise was ever reached, making
        # generate() fail with a CalledProcessError rather than the intended
        # test scenario. Confirmed this was NOT an artefact of the I-2 fix:
        # assign_group("99.1.1") raises UnclassifiedAnchorError unconditionally
        # (verified directly via a real assign_group() call), so this fixture
        # would have failed identically before that fix too (exit 5 vs 6,
        # same CalledProcessError either way, `check=True` raises on ANY
        # non-zero code). Replaced with "11.4.206" (falls in the real
        # git-and-data-safety numeric range) and "12.7" (a real
        # EXPLICIT_ID_GROUPS key) -- both independently confirmed, via a
        # direct extract_anchors() scan of the real corpus AND a separate
        # anchored grep for the exact heading form, to have NO existing
        # heading-form definition anywhere in Constitution.md (they appear
        # only as CITATIONS in other anchors' prose), so this fixture cannot
        # collide with or corrupt any real anchor's data.
        with open(synthetic_src, "w") as f:
            f.write(
                "### §11.4.206 — A synthetic project-specific anchor for oracle testing\n\n"
                "**Classification:** project-specific (§11.4.17) — this anchor exists only "
                "in this synthetic fixture to prove the extraction path for the "
                "`project-specific` value is genuinely exercised, since the real corpus "
                "has none.\n\n"
                "### §12.7 — A synthetic universal anchor, for contrast\n\n"
                "Classification: universal\n\n"
            )
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", synthetic_src,
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)
        with open(index_out) as f:
            idx = yaml.safe_load(f)
        generator_count = sum(1 for a in idx["anchors"] if a["classification"] == "project-specific")

        # Pattern fixed 2026-09-26 (found running this test for real, the
        # FIRST place this exact grep pattern ever met a genuine positive
        # case): the plan's original r"Classification:\s*project-specific"
        # cannot match the synthetic fixture's own bold-markdown form
        # ("**Classification:** project-specific") because `\s*` only
        # skips WHITESPACE, never the literal "**" closing-bold asterisks
        # sitting between the colon and the value -- confirmed directly
        # (old pattern: 0 matches; new pattern: 1 match on the identical
        # text). "\**" added to tolerate zero-or-more literal asterisks,
        # mirroring anchor_lib.py's own _CLASSIFICATION_LINE_RE bold-marker
        # tolerance (`\*{0,2}`) -- the two extraction paths must agree on
        # what a real bold-form Classification line even looks like, or
        # this "independent oracle" isn't independently checking the same
        # thing. Re-confirmed this introduces no false positive against the
        # real corpus (still an exact 0 match, per this same anchor's other
        # test below).
        grep_count = int(subprocess.run(
            ["grep", "-icE", r"Classification:\**\s*project-specific", synthetic_src],
            capture_output=True, text=True,
        ).stdout.strip() or "0")

        assert generator_count == 1, f"expected exactly 1 project-specific anchor in the synthetic fixture, got {generator_count}"
        assert grep_count == 1, f"independent grep expected exactly 1 match in the synthetic fixture, got {grep_count}"
        assert generator_count == grep_count
        print(f"synthetic project-specific oracle PASS: {generator_count} == {grep_count} == 1")


def test_project_specific_count_matches_an_independently_derived_manual_count():
    # FR-002's Checked-by clause (`/speckit-analyze` remediation, finding C2):
    # "a scripted query against it returns a result set matching a manual
    # count from the source Markdown." T016's other two tests only check the
    # YAML's INTERNAL self-consistency (the same generator that WROTE the
    # classification field grading its own output) — that is not an
    # independent oracle per Principle IV ("the same actor MUST NOT both
    # pick the test inputs and write the fix"). This test cross-checks
    # against a count derived by a DIFFERENT tool/path (raw shell `grep -c`
    # on the source Markdown, never anchor_lib's own regex) so the two
    # counts genuinely disagree if the generator's classification logic is
    # wrong, rather than merely echoing it. NOTE (finding D3): against the
    # REAL corpus this always compares 0 == 0 (see the synthetic-fixture
    # test above, which is what actually exercises the detection logic
    # with a positive case) — this test remains valuable as confirmation
    # that BOTH extraction paths agree the real corpus has genuinely zero,
    # not as the sole oracle for the `project-specific` value.
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        subprocess.run(["python3", GEN, "generate", "--source", "constitution/Constitution.md",
                         "--groups-dir", groups_dir, "--index-out", index_out], check=True)
        with open(index_out) as f:
            idx = yaml.safe_load(f)
        generator_count = sum(1 for a in idx["anchors"] if a["classification"] == "project-specific")

        # Independent oracle: raw grep, no anchor_lib import, no shared code
        # path with the generator's own classification extraction. Same
        # bold-marker-tolerant pattern as the synthetic-fixture test above
        # (2026-09-26 fix) for consistency; re-confirmed this still returns
        # exactly 0 against the real corpus (no false positive introduced).
        grep_count = int(subprocess.run(
            ["grep", "-icE", r"Classification:\**\s*project-specific", "constitution/Constitution.md"],
            capture_output=True, text=True,
        ).stdout.strip() or "0")
        assert generator_count == grep_count, (
            f"generator reports {generator_count} project-specific anchors, "
            f"but an independent grep of the source counts {grep_count} — "
            f"one of the two extraction paths is wrong"
        )
        print(f"independent cross-check PASS: {generator_count} == {grep_count}")

if __name__ == "__main__":
    test_every_anchor_has_classification_and_explicit_gate_key()
    test_filter_by_classification_matches_plain_yaml_list_comprehension()
    test_project_specific_classification_is_detected_via_synthetic_fixture()
    test_project_specific_count_matches_an_independently_derived_manual_count()
    print("PASS")
