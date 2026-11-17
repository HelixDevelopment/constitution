#!/usr/bin/env python3
# docs/qa/tracker_intake_2026_11_12_v2/apply_v2.py -- one-shot data fix of the tracker-intake vehicle
# (round 2 of the vehicle, after the independent review NO-GO in
# docs/qa/tracker_intake_2026_11_12/sources/review_tracker_intake.md).
#
# Every change goes through the workable-items engine (update, close, obsolete-details, add);
# nothing writes the SQLite file directly. The script refuses to run unless the database holds the
# exact texts it was written against (each replaced text must occur exactly once), so a second run,
# or a run on another database, changes nothing and exits 1.
#
# Usage: python3 -I apply_v2.py --wi <workable-items binary> --db docs/workable_items.db
#        [--by <states-updated-by handle>] [--dry-run]
# Exit: 0 applied; 1 precondition failed (nothing written); 2 usage; 3 an engine call failed
#       (the calls before it stay applied; the log names the failed call).
# Evidence class: gate-logic only (section 11.4.289); it records tracker text, it proves no defect.
import argparse
import re
import sqlite3
import subprocess
import sys

import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
ORIGIN = "tracker-intake vehicle 2026-11-12"
SRC = "docs/qa/tracker_intake_2026_11_12/sources/"
V2 = "docs/qa/tracker_intake_2026_11_12_v2/"
REC = "docs/operator_decisions/2026-11-12_relayed_decisions.md"
SOURCE_NAMES = (
    "review_retest_items.md", "rtfix_lander_items.md", "review_multiforge_r4.md", "review_gitlab_prerelease.md",
    "review_gitlab_prerelease_mutants.txt", "review_fix227_r8.md", "review_retest_items_logs/",
    "review_tracker_intake.md",
)
FOREIGN_FIX227 = "Foreign ids (fix227 vehicle namespace; on this tracker these numbers are other items): CON-300..CON-311, CON-310, CON-311"
FOREIGN_CON046 = (
    "Foreign ids (con046 vehicle namespace, written before each re-mint; on this tracker these numbers are other items "
    "or do not exist): CON-083, CON-108, CON-109, CON-146, CON-147, CON-194, CON-195, CON-280, CON-281"
)
METHOD = (" Method: every open item compared by title and description word overlap and by shared file names "
          "(" + V2 + "inventory/).")
TAG = (" CON-227 and CON-233 name scripts/release/tag_and_release.sh for other defects (rel734 reviewer survivors; "
       "gitea exit code 3).")
DUP = {
    "CON-299": "DISTINCT (the umbrella of this intake; no other open item covers it).",
    "CON-300": "DISTINCT (no open item asks for a recursive fetch and pull of all upstreams).",
    "CON-301": "DISTINCT.",
    "CON-302": "DISTINCT.",
    "CON-303": "DISTINCT.",
    "CON-304": ("DISTINCT-but-similar of CON-183 and CON-237 (both name test_consumer_required_helper.sh for other "
                "defects: CON-183 the Part 4 skip under the mutation harness, CON-237 the dash failure); related "
                "CON-092, CON-093, CON-102."),
    "CON-305": "DISTINCT.",
    "CON-306": ("DISTINCT-but-similar of CON-092 (an instance of the CON-092 class, skip per section and not the whole "
                "test; CON-092 covers the consumer_required.sh tests, this item token_stability under the new layout "
                "probe); class parent link: CON-092; related CON-093."),
    "CON-307": "DISTINCT.",
    "CON-308": ("SAME-DEFECT of CON-262 (its acceptance criterion already says run_all.sh reports a 77 as SKIP); this "
                "item is closed Obsolete, reason duplicate-of, superseding CON-262, and its context is appended to "
                "CON-262. CON-243 names the same run_all.sh behaviour (plus tier awareness) and is a second open "
                "head; that CON-243 / CON-262 overlap is pre-existing and its merge stays UNDECIDED for the lander or "
                "the operator (section 11.4.214(3)). CON-145 and CON-261 name run_all.sh for other defects."),
    "CON-309": ("DISTINCT-but-similar of CON-092 (an instance of the CON-092 class, section-level skip, as the item "
                "says); class parent link: CON-092; related CON-093."),
    "CON-310": "DISTINCT.",
    "CON-311": ("DISTINCT-but-similar of CON-174 (test_check_deps.sh signal race; the test_check_deps leak counts quoted "
                "here may share that cause, UNCONFIRMED) and CON-293 (the runner self-test lost files from its own "
                "mktemp tree; a different symptom)."),
    "CON-312": "DISTINCT.",
    "CON-313": "DISTINCT.",
    "CON-314": ("DISTINCT-but-similar of CON-271 (commits whose Roadmap-Item trailer is not an engine id; another "
                "vehicle) and CON-329 (the same lander duty for the fix227 vehicle)."),
    "CON-315": "DISTINCT-but-similar of CON-327 (the same explicit --hostname, on the fix227 re-application)." + TAG,
    "CON-316": "DISTINCT." + TAG,
    "CON-317": "DISTINCT-but-similar of CON-326 (released_at validation on the fix227 re-application)." + TAG,
    "CON-318": "DISTINCT." + TAG,
    "CON-319": "DISTINCT." + TAG,
    "CON-320": "DISTINCT." + TAG,
    "CON-321": ("DISTINCT-but-similar of CON-328 (adopting these reviewer mutants into fix227's catalogue) and CON-227 "
                "(other reviewer survivors, of the rel734 change, in the same script). CON-233 names the same script "
                "for another defect."),
    "CON-322": "DISTINCT." + TAG,
    "CON-323": "DISTINCT." + TAG,
    "CON-324": "DISTINCT." + TAG,
    "CON-325": "DISTINCT.",
    "CON-326": "DISTINCT-but-similar of CON-317 (released_at validation on the base change)." + TAG,
    "CON-327": "DISTINCT-but-similar of CON-315 (the same --hostname on the base change)." + TAG,
    "CON-328": ("DISTINCT-but-similar of CON-321 (the reviewer mutants that survive and that this catalogue must kill) and CON-227 (the rel734 "
                "reviewer survivors that the same family of tests must kill)."),
    "CON-329": ("DISTINCT-but-similar of CON-271 (commits whose Roadmap-Item trailer is not an engine id; another "
                "vehicle) and CON-314 (the same lander duty for the multiforge vehicle)."),
    "CON-330": "DISTINCT (it amends a fix227 vehicle item, not an item of this tracker).",
    "CON-331": "DISTINCT.",
    "CON-332": "DISTINCT.",
    "CON-333": "DISTINCT.",
}

REPO_HITS_ROWS = [
    ("vasic-digital/sftp", 1922, 991), ("vasic-digital/caf-cline", 107, 6), ("vasic-digital/HelixAgent", 30, 16),
    ("vasic-digital/LLMsVerifier", 25, 9), ("HelixDevelopment/agent", 22, 16), ("vasic-digital/caf-codex", 18, 2),
    ("vasic-digital/ATMOSphere-SmartTube", 13, 2), ("vasic-digital/ATMOSphere-Rhythm-Player", 11, 2),
    ("vasic-digital/caf-gemini-cli", 11, 1), ("vasic-digital/caf-bridle", 9, 3), ("vasic-digital/Integrations", 7, 7),
    ("vasic-digital/Yole", 7, 4), ("HelixDevelopment/qa", 5, 2), ("vasic-digital/caf-forge", 5, 3),
    ("vasic-digital/helix_qa", 5, 2), ("vasic-digital/caf-x-cmd", 4, 2), ("vasic-digital/caf-warp", 3, 3),
    ("vasic-digital/ATMOSphere-TorrServe", 2, 1), ("vasic-digital/catalogizer", 2, 2), ("HelixDevelopment/seller", 1, 1),
    ("HelixDevelopment/translate", 1, 1), ("Helix-Track/Core", 1, 1), ("vasic-digital/ATMOSphere-Presenter", 1, 1),
    ("vasic-digital/caf-codename-goose", 1, 1), ("vasic-digital/caf-vtcode", 1, 1), ("vasic-digital/herald", 1, 1),
    ("vasic-digital/Pure_v2_Firmware", 1, 1),
]
assert sum(h for _, h, _ in REPO_HITS_ROWS) == 2216 and sum(r for _, _, r in REPO_HITS_ROWS) == 1082
assert len(REPO_HITS_ROWS) == 27

CON333_WHAT = (
    "**What:** Operator decision, 2026-11-12 about 23:30 CET (record " + REC + ", decision 7): secrets in other "
    "repositories: report only (paths and key kinds, no values); the operator rotates; two huge Android repositories "
    "stay skipped and recorded. Scan result (no value and no path is copied here), in two units. (1) Finding rows: "
    "1082, each one unique (repository, kind, path); rows by kind: jwt 1000, curl-auth-header 28, gcp-api-key 24, "
    "private-key 12, curl-auth-user 8, huggingface-access-token 3, kubernetes-secret-yaml 2, aws-access-token 2, "
    "rapidapi-access-token 1, github-pat 1, github-fine-grained-pat 1. (2) Hits: 2216 matching lines in total (one "
    "row can hold several hits). 27 repositories have findings; per repository, hits / rows: "
    + ", ".join("%s %d / %d" % t for t in REPO_HITS_ROWS)
    + ". Of the 1000 jwt rows, 991 are in vasic-digital/sftp. Whether any row is a live credential or a test fixture: "
    "UNKNOWN (not classified here). Skipped as over 3 GB (scan file SKIPPED.tsv): vasic-digital/ATMOSphere-Android-15 "
    "and vasic-digital/ATMOSphere-Android-15-Main."
)

# Specific replacements: (old, new), applied to the ORIGINAL text first; each old must occur exactly once.
SPECIFIC = {
    "CON-299": [
        ("Children are listed in the tracker history of each item as 'Umbrella: <this id>'.",
         "The children are the items whose Parent / links line names 'umbrella CON-299'; that link lives in each "
         "child's description only (the history rows of these items carry no umbrella reason)."),
        ("The sources are: operator request 2026-11-12 22:26, the retest-vehicle review (review_retest_items.md) and "
         "its lander list (rtfix_lander_items.md), the multiforge round-4 review, the GitLab pre-release review, the "
         "fix227 round-8 landing notes, the identity-guard round-4 operator decision and the operator decisions of "
         "2026-11-12 23:30.",
         "The sources (copies in " + SRC + ", checksums in its SHA256SUMS): the operator request of 2026-11-12 22:26; "
         "the retest-vehicle review (review_retest_items.md, logs review_retest_items_logs/) and its lander list "
         "(rtfix_lander_items.md); the multiforge round-4 review (review_multiforge_r4.md); the GitLab pre-release "
         "review (review_gitlab_prerelease.md, mutants review_gitlab_prerelease_mutants.txt); the fix227 round-8 "
         "review (review_fix227_r8.md); and the seven operator decisions of 2026-11-12 about 23:30 CET, recorded in "
         + REC + " with one disposition each: 1 identity guard -> CON-331; 2 CON-046 screen rerun and description "
         "restore -> CON-046, whose text is restored and now carries the rerun decision; 3 security apply -> CON-332; 4 Jev "
         "CMA_JEV_PREFER until the toolkit failover fix lands -> {N1}; 5 orphan reaping and 6 disk prunes -> one-off "
         "authorisations, no item (nothing is owed); 7 secrets report only -> CON-333. Review follow-ups of this "
         "vehicle's own review (review_tracker_intake.md): {N2} (summary width), {N3} (history attribution), {N4} "
         "(engine fail-open), {N5} (content lint wiring)."),
        ("Parent / links: all items minted by this vehicle; fix227 vehicle (CON-310, CON-311 live there, not on main 02c10935)",
         "Parent / links: all items minted by this vehicle; fix227 vehicle (CON-310, CON-311 live there, not on main 02c10935)\n"
         + FOREIGN_FIX227),
    ],
    "CON-300": [
        ("Related: order memory order-sync-all-upstreams-2026-11-12.",
         "Related: order memory order-sync-all-upstreams-2026-11-12. Operator reminder 2026-11-13 00:34 (relayed): "
         "regularly fetch and pull the latest main from all upstreams; recorded in " + REC + "."),
        ("related CON-296 (GitHub issues sync) is a different feature, not a parent",
         "related: anchor section 11.4.296 (GitHub Issues as a source of workable items; an anchor, not a tracker "
         "item) is a different feature, not a parent"),
    ],
    "CON-301": [
        ("reproduced by the reviewer in a mutant copy (reproduced-host-fixture class, evidence in the reviewer logs "
         "review_retest_items_logs/).",
         "the reviewer ran the mutant in a copy on the host (logs in review_retest_items_logs/); a test-instrumentation "
         "Task, so no section 11.4.294 state is set."),
    ],
    "CON-308": [
        ("Pre-existing behaviour read from the script; not run as a batch (host load). Reproduction state: UNREPRODUCED.",
         "Pre-existing behaviour read from the script; not run as a batch (host load). The reproduction and "
         "investigation states are this item's state fields (section 11.4.294(A))."),
    ],
    "CON-311": [
        ("Reproduction state: reproduced-host-fixture once (dir removed by the fixer with a guarded rm after recording). "
         "Investigation: in-progress (cause class known, exact sender not identified).",
         "Observed once by the retest-vehicle fixer after one full run; the directory was removed with a guarded rm "
         "after it was noted and no evidence file was kept, so it is not a recorded reproduction (section 11.4.292(C), "
         "11.4.294(C)). The state fields hold the reproduction (none recorded) and the investigation (in progress: the "
         "cause class is known, the exact sender is not identified)."),
    ],
    "CON-321": [
        ("Results file review_gitlab_prerelease_mutants.txt in the reviewer scratch; reproduced-host-fixture by the reviewer.",
         "Results file review_gitlab_prerelease_mutants.txt (a copy of the reviewer's scratch file); the reviewer ran "
         "each mutant on the host. A test-instrumentation Task, so no section 11.4.294 state is set."),
    ],
    "CON-329": [
        ("are NOT the ids minted here; umbrella CON-299",
         "are NOT the ids minted here; umbrella CON-299\n" + FOREIGN_FIX227),
    ],
    "CON-330": [
        ("are NOT the ids minted here; umbrella CON-299",
         "are NOT the ids minted here; umbrella CON-299\n" + FOREIGN_FIX227),
    ],
    "CON-331": [
        ("git identity guard vehicle (idg3.Yabv, head 8c18b145 at round 3, round-4 evidence idguard_r4_evidence); "
         "docs/operator_decisions",
         "git identity guard vehicle (scratch clone idg3.Yabv and round-4 evidence idguard_r4_evidence (ephemeral: "
         "session-scratchpad locations, not kept), head 8c18b145 at round 3); docs/operator_decisions"),
        ("Decision record; not a defect.",
         "Decision record; not a defect. Recorded in " + REC + " (decision 1)."),
    ],
    "CON-332": [
        ("Not a defect; operational follow-through.",
         "Not a defect; operational follow-through. Recorded in " + REC + " (decision 3)."),
        ("related CON-296 not a parent",
         "related: anchor section 11.4.296 (an anchor, not a tracker item), not a parent"),
    ],
}
CON333_PARAS = {
    "what_prefix": "**What:** Operator decision, 2026-11-12 about 23:30 CET: secrets in other repositories:",
    "scope_old": ("the 27 repositories above (read-only report; no change is made to them by this item); scan files "
                  "under the session scratchpad"),
    "scope_new": ("the 27 repositories above (read-only report; no change is made to them by this item). The scan files "
                  "(real_by_path.txt with the per-file paths, SKIPPED.tsv, CONTROLS.tsv) are in the security follow-up "
                  "investigation's session scratchpad (ephemeral: lost when that scratchpad is cleaned) and stay out of "
                  "the tracker and the repository on purpose."),
    "ctx_old": "Scan by the security follow-up investigation (tool and rules: see the scan directory; control needles in CONTROLS.tsv).",
    "ctx_new": ("Scan by the security follow-up investigation (tool and rules: in its scan directory, described above; "
                "control needles in its CONTROLS.tsv)."),
    "acc_old": ("The operator has the report (repo names, kinds, counts, per-file paths on request), rotation by the "
                "operator is recorded per repository, no value is ever written to the tracker, logs or commits (section "
                "11.4.10), the two skipped repositories are recorded as skipped."),
    "acc_new": ("The operator has the report (repository names, kinds, counts; per-file paths on request); a copy of the "
                "per-file report is kept where the operator decides, outside the tracker and the repository, before the "
                "scan files are lost (location UNCONFIRMED: an operator decision is owed, section 11.4.66); rotation by "
                "the operator is recorded per repository; no value is ever written to the tracker, logs or commits "
                "(section 11.4.10); the two skipped repositories are recorded as skipped."),
}

CON262_APPEND = (
    "\n\nContext added 2026-11-13 by the tracker-intake vehicle (umbrella CON-299; section 11.4.214, link only for an "
    "open match): the retest vehicle (lander list " + SRC + "rtfix_lander_items.md, item C-2) makes six fastcycle units "
    "exit 77 with reason=topology_unsupported in the canon-alone layout, so run_all.sh reports FAIL for them while "
    "run_full_suite.sh reports SKIP. The duplicate CON-308 that recorded this is closed Obsolete, duplicate-of this "
    "item. A paired mutant for the run_all.sh mapping of 77 belongs to this item's acceptance. Candidate duplicate: "
    "CON-243 (the same run_all.sh behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3))."
)
CON046_APPEND = (
    "\n\nRelayed operator decision, 2026-11-12 about 23:30 CET (record " + REC + ", decision 2): let the third full "
    "screen finish, then rerun all three screens on one calendar day (the current run crosses midnight); restore this "
    "description through the engine (done by the tracker-intake vehicle, see above). Not executed by the record. "
    "The docs/qa/con046_review/ paths cited above are files of the con046 vehicle (head 7bdffcf6); they are not on "
    "main 02c10935 and resolve only after that vehicle lands.\n"
    + FOREIGN_CON046
)

ORIGIN_LINE = ("Origin: tracker-intake vehicle 2026-11-12 (sections 11.4.202, 11.4.210, 11.4.148, 11.4.197, 11.4.214); "
               "intake only, not a fix. Added in round 2 of the vehicle after its review (" + SRC
               + "review_tracker_intake.md). Ids minted here on base 02c10935 are re-minted by the lander if they collide "
               "(section 11.4.214).")


def new_items():
    return [
        ("N1", "Task", "Medium",
         "claude_toolkit Jev endpoint failover fix is owed: the operator exports CMA_JEV_PREFER=jev-typesafe until it lands",
         "**What:** Operator decision, 2026-11-12 about 23:30 CET (record " + REC + ", decision 4): the operator exports "
         "CMA_JEV_PREFER=jev-typesafe until the claude_toolkit failover fix lands. That fix is owed work and had no "
         "tracker item (review of the tracker-intake vehicle, finding I8). UNKNOWN: the failover defect in detail (only "
         "the relayed decision is held) and whether the claude_toolkit repository tracks it.\n\n"
         "**Affected scope / file-scope manifest:**\nsubmodules/claude_toolkit (Jev endpoint selection and failover; "
         "files UNKNOWN); the operator's environment (CMA_JEV_PREFER)\n\n"
         "**Reproduction / context:**\nNot reproduced here; the decision is the only record. Never print or store a "
         "credential while investigating (section 11.4.10).\n\n"
         "**Acceptance criteria:**\nThe failover defect is described from evidence (section 11.4.102), fixed upstream "
         "in claude_toolkit, the pin is bumped (section 11.4.288(D)) and the operator is told the CMA_JEV_PREFER "
         "workaround can be dropped; until then the workaround stays recorded.\n\n"
         "Parent / links: umbrella CON-299; context anchor section 11.4.279 (decision-model detection)\n"
         "Duplicate check (section 11.4.214): DISTINCT (no open item names the Jev failover)." + METHOD + "\n"
         + ORIGIN_LINE, None),
        ("N2", "Task", "Low",
         "Issues_Summary.md and Fixed_Summary.md print the whole description in the Summary column (export.go "
         "summaryDescription), so a row reaches 6450 characters",
         "**What:** summaryDescription in scripts/workable-items/cmd/workable-items/export.go returns the whole "
         "description, so a long description makes an unreadable summary row (section 11.4.91). Measured at bundle "
         "head 1a307322: 15 summary rows over 2000 characters (12 on base 02c10935); the CON-046 row is 6450 characters "
         "after its description was restored. Review finding I7 (generator behaviour, not the intake data).\n\n"
         "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/export.go "
         "(summaryDescription) and its tests; docs/Issues_Summary.md and docs/Fixed_Summary.md (regenerated)\n\n"
         "**Reproduction / context:**\nMeasured by counting the Summary rows of docs/Issues_Summary.md at 02c10935 and "
         "1a307322: " + V2 + "inventory/summary_row_widths.txt. Not a defect of stored data.\n\n"
         "**Acceptance criteria:**\nThe summary cell is bounded (for example the first sentence, or a fixed character "
         "budget with an ellipsis) with a test; both summary files are regenerated; independent review.\n\n"
         "Parent / links: umbrella CON-299\n"
         "Duplicate check (section 11.4.214): DISTINCT (no open item names the summary width)." + METHOD + "\n"
         + ORIGIN_LINE, None),
        ("N3", "Bug", "Low",
         "workable-items add records the Opened history row as by=User whatever --created-by says (crud.go "
         "recordHistory call)",
         "**What:** addCmd in scripts/workable-items/cmd/workable-items/crud.go calls recordHistory(tx, id, \"Opened\", "
         "\"User\", \"\", \"\"), so every add records by=User in item_history even when --created-by names an agent "
         "(section 11.4.34 source attribution; item_history.by is the closed set AI, User). The 35 intake items of "
         "2026-11-12 have created_by Conductor and history by User (review finding I9).\n\n"
         "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/crud.go and its tests\n\n"
         "**Reproduction / context:**\nReproduced on the host against a scratch copy of the vehicle database: " + V2
         + "engine_failopen_repro.txt (section I9; script engine_repro.sh in the same directory). The hard-coded "
         "literal is the likely cause (read from source); the experiment that changes the literal and sees the row "
         "change is not run here.\n\n"
         "**Acceptance criteria:**\nadd maps --created-by onto by (AI for an agent handle, User for the operator, the "
         "rule recorded) or takes an explicit flag; a RED test on the old behaviour turns GREEN; existing history rows "
         "are not rewritten.\n\n"
         "Parent / links: umbrella CON-299\n"
         "Duplicate check (section 11.4.214): DISTINCT (no open item names the history attribution of add)." + METHOD
         + "\n" + ORIGIN_LINE,
         ("reproduced-host-fixture", "in-progress",
          "history Opened row of an item added with --created-by Conductor reads by=User",
          "bash " + V2 + "engine_repro.sh <workable-items binary> <scratch copy of docs/workable_items.db>")),
        ("N4", "Bug", "Medium",
         "workable-items fail-open: update --status outside the closed set exits 0 and changes nothing; add with an "
         "unknown type creates a Task",
         "**What:** Measured: update --status Done and update --status Bogus print 'updated' and exit 0 while the status "
         "stays Queued; add Story exits 0 and creates the item as Type Task. The caller cannot tell that its request was "
         "not applied (section 11.4.201(4) fail closed; section 11.4.15 and 11.4.16 closed sets). Reviewer mutants M4 "
         "and M5 of the tracker-intake review.\n\n"
         "**Affected scope / file-scope manifest:**\nscripts/workable-items/cmd/workable-items/crud.go (status handling "
         "of update, normalizeType in add) and their tests\n\n"
         "**Reproduction / context:**\n" + V2 + "engine_failopen_repro.txt, sections M4 and M5 (control: 'In progress' "
         "is accepted and changes the row; script engine_repro.sh in the same directory).\n\n"
         "**Acceptance criteria:**\nBoth exit non-zero (usage, 2) with a message naming the closed set and change "
         "nothing; RED tests on the old behaviour turn GREEN with paired mutants; accepted aliases, if any, are a "
         "documented table.\n\n"
         "Parent / links: umbrella CON-299\n"
         "Duplicate check (section 11.4.214): DISTINCT (no open item names these two fail-open paths)." + METHOD + "\n"
         + ORIGIN_LINE,
         ("reproduced-host-fixture", "not-started",
          "update --status Bogus exits 0 and the status is unchanged; add Story exits 0 and the type is Task",
          "bash " + V2 + "engine_repro.sh <workable-items binary> <scratch copy of docs/workable_items.db>")),
        ("N5", "Task", "Medium",
         "Content lint for intake batches: wire scripts/workable-items/intake_lint.py into the reporting and landing "
         "paths and the pre-build sweep",
         "**What:** validate and diff prove the closed sets and the DB-to-Markdown sync, not what a description says. The "
         "review of the tracker-intake vehicle found two wrong facts (a section 11.4.214 duplicate and an anchor number "
         "cited as an item id) that passed both, and its data mutants M2, M3, M9, M10 and M11 survived. Round 2 of the "
         "vehicle adds scripts/workable-items/intake_lint.py (read-only; gate-logic evidence only) and runs it on its own "
         "items; nothing calls it yet (scripts/reporting/report_item.sh, the lander procedure, the pre-build sweep).\n\n"
         "**Affected scope / file-scope manifest:**\nscripts/workable-items/intake_lint.py, scripts/reporting/report_item.sh, "
         "the lander procedure, tests/workable_items/test_intake_lint.sh\n\n"
         "**Reproduction / context:**\n" + V2 + "README.md (reviewer mutant table and the RED run on 1a307322).\n\n"
         "**Acceptance criteria:**\nEvery intake (reporting directive or lander batch) runs the lint on its new items and "
         "refuses on a finding; a gate wrapper with a paired mutation test exists, or a registered deferral row names it "
         "(section 11.4.227(A)); independent review.\n\n"
         "Parent / links: umbrella CON-299\n"
         "Duplicate check (section 11.4.214): DISTINCT (no open item asks for a description-content lint)." + METHOD
         + "\n" + ORIGIN_LINE, None),
    ]


def generic(text):
    for name in SOURCE_NAMES:
        text = re.sub(r"(?<![\w/.-])" + re.escape(name), SRC + name, text)
    text = text.replace("bundle retest_new1-4.bundle, head",
                        "bundle retest_new1-4.bundle (ephemeral: a session-scratchpad file, not kept), head")
    text = text.replace("bundle mf_r4_bundle.6mLoJd/multiforge_r4.bundle head",
                        "bundle mf_r4_bundle.6mLoJd/multiforge_r4.bundle (ephemeral: a session-scratchpad file, not kept) head")
    return text


def add_dup_line(iid, text):
    line = "Duplicate check (section 11.4.214): " + DUP[iid] + METHOD
    m = re.search(r"^Origin: ", text, re.M)
    if not m:
        raise SystemExit("precondition: %s has no Origin line" % iid)
    return text[:m.start()] + line + "\n" + text[m.start():]


def one(text, old, iid):
    n = text.count(old)
    if n != 1:
        raise ValueError("%s: expected exactly one occurrence, found %d: %r" % (iid, n, old[:70]))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wi", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--by", default="Claude (tracker-intake round-2 fixer, Opus 5.5)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    con = sqlite3.connect("file:%s?mode=ro" % a.db, uri=True)
    rows = dict(con.execute("select atm_id, description from items where current_location='Issues'"))
    con.close()
    intake = sorted(i for i, d in rows.items() if ORIGIN in d)
    if intake != sorted(DUP):
        print("precondition: intake set differs from the one this script was written for: %s" % intake, file=sys.stderr)
        return 1
    plan = {}
    try:
        for iid in intake:
            text = rows[iid]
            for old, new in SPECIFIC.get(iid, []):
                one(text, old, iid)
                text = text.replace(old, new)
            if iid == "CON-333":
                one(text, CON333_PARAS["what_prefix"], iid)
                start = text.index(CON333_PARAS["what_prefix"])
                end = text.index("\n\n", start)
                text = text[:start] + CON333_WHAT + text[end:]
                for k in ("scope", "ctx", "acc"):
                    one(text, CON333_PARAS[k + "_old"], iid)
                    text = text.replace(CON333_PARAS[k + "_old"], CON333_PARAS[k + "_new"])
            text = add_dup_line(iid, generic(text))
            plan[iid] = text
        for iid, app in (("CON-262", CON262_APPEND), ("CON-046", CON046_APPEND)):
            if app.strip() in rows[iid]:
                raise ValueError("%s already carries the appended text" % iid)
            plan[iid] = rows[iid] + app
    except ValueError as e:
        print("precondition: %s" % e, file=sys.stderr)
        return 1

    def call(args):
        print("$ workable-items " + " ".join(x if len(x) < 90 else "<%d chars>" % len(x) for x in args))
        if a.dry_run:
            return
        p = subprocess.run([a.wi] + args, capture_output=True, text=True)
        out = (p.stdout + p.stderr).strip()
        print("  -> rc=%d %s" % (p.returncode, out[:300]))
        if p.returncode != 0:
            raise SystemExit(3)

    # 1. new items first, so the umbrella can name their ids
    ids = {}
    con = sqlite3.connect("file:%s?mode=ro" % a.db, uri=True)
    nums = [int(i.split("-")[1]) for (i,) in con.execute("select atm_id from items") if i.startswith("CON-")]
    con.close()
    nxt = max(nums) + 1
    for key, typ, sev, title, desc, states in new_items():
        iid = "CON-%03d" % nxt
        nxt += 1
        ids[key] = iid
        args = ["add", typ, sev, "--db", a.db, "--id", iid, "--title", title, "--description", desc,
                "--created-by", "Claude"]
        if states:
            rs, ivs, sig, red = states
            args += ["--reproduction-state", rs, "--investigation-state", ivs, "--states-updated-by", a.by,
                     "--reproduction-surface", "host-only", "--reproduction-evidence", V2 + "engine_failopen_repro.txt",
                     "--reproduction-env", "scratch copy of docs/workable_items.db at 1a307322; engine built from that tree",
                     "--reproduction-signature", sig, "--reproduction-red-cmd", red]
        call(args)
    plan["CON-299"] = plan["CON-299"].format(**ids)
    # 2. descriptions
    for iid in sorted(plan):
        call(["update", "--db", a.db, "--id", iid, "--description", plan[iid]])
    # 3. states (section 11.4.294(A): the column is the source)
    for iid, rs, ivs in (("CON-308", "UNREPRODUCED", "not-started"), ("CON-311", "UNREPRODUCED", "in-progress"),
                         ("CON-046", "UNREPRODUCED", None)):
        args = ["update", "--db", a.db, "--id", iid, "--reproduction-state", rs, "--states-updated-by", a.by]
        if ivs:
            args += ["--investigation-state", ivs]
        call(args)
    # 4. CON-308 is the same defect as the open CON-262 (section 11.4.214: link, never a second open id)
    ev = V2 + "inventory/repro_I1_I2.txt"
    call(["close", "CON-308", "--db", a.db, "--status", "obsolete", "--evidence", ev])
    call(["obsolete-details", "CON-308", "--db", a.db, "--since", "2026-11-13", "--reason", "duplicate-of",
          "--superseding", "CON-262", "--evidence", ev])
    print("new ids: " + ", ".join("%s=%s" % kv for kv in sorted(ids.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
