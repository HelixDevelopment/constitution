#!/bin/sh
# =============================================================================
# T022 RED test (SpecKit-004 "fast-dev-cycles", Phase 3 / User Story 1;
# plan.md T-A08; FR-001, SC-001).
# =============================================================================
#
# Purpose: prove, BEFORE any T-A08/T040 implementation exists, that:
#   (A) TODAY docs/build/resources/builds.tsv build rows carry only a
#       resource-SAMPLER lifecycle status (written by
#       scripts/build_resource_monitor.sh) and NO build/QA "verdict" field at
#       all -- confirmed against the REAL, currently-tracked project file,
#       not a fixture (§11.4.6 no-guessing: measured, not assumed);
#   (B) golden-bad: a row whose "verdict" was naively copied from its sampler
#       `status` (the REAL T027 mutation named for this exact task -- see the
#       "T027 MUTATION CORRECTION" note below) MUST be refused, because
#       KILLED describes the resource-monitor PROCESS having been killed
#       alongside the containerized build (scripts/build_containerized.sh's
#       EXIT/INT/TERM/HUP trap `_build_res_emergency_stop`, lines ~400-415),
#       never whether the built artifact passed any check;
#   (C) golden: a build event + a flash/deploy event sharing ONE artifact
#       fingerprint join into a single verdict+deploy record;
#   (D) negative-control (added here for the mandatory C-005 self-validation
#       triple, common-conventions.md): a row whose sampler was KILLED but
#       whose verdict field is genuinely, separately valid must NOT be
#       refused -- proving the golden-bad check targets the INVALID VERDICT
#       VALUE, never merely "was the sampler killed".
#
# T027 MUTATION CORRECTION (§11.4.6 no-guessing -- verified against the real
# spec, not copied blind from dispatch text): the dispatch instructions for
# this task named the mutation "default a missing stage to 0" as "the T027
# mutation for this area". Verified against specs/004-fast-dev-cycles/tasks.md
# line 109 (T027) and specs/004-fast-dev-cycles/plan.md's own T-A08
# "Protecting tests" line: "default a missing stage to 0" is T-A09's mutation
# (constitution/scripts/fastcycle/cycle/cycle_report.py's own RED test,
# test_cycle_report_red.sh), NOT T-A08's. The REAL T-A08 mutation, named
# verbatim in BOTH tasks.md T027 ("emit sampler status into the verdict
# field") and plan.md T-A08's Protecting-tests line ("paired mutation: emit
# sampler status into the verdict field -> the golden-bad FAILs"), is exactly
# what the golden-bad fixture below already encodes: copying builds.tsv's
# `status` column straight into a `verdict` field. Once
# constitution/scripts/fastcycle/cycle/build_deploy_qa_events.py exists and
# this test is GREEN, applying that mutation to it (making `verdict` a
# straight alias of `status` instead of an independently-validated field)
# MUST flip the golden-bad fixture below (build_id=2c2e90d9277-20260515T104444Z,
# status=KILLED, verdict=KILLED) from refused (exit 1, "golden-bad" ok=true)
# to accepted (exit 0) -- that flip is what T027 observes and stores under
# qa-results/fastcycle/us1/mutations/.
#
# REAL DATA MEASURED (2026-09-28, control-needle-proven per §11.4.273 --
# Section A below re-proves this live rather than trusting this comment):
#   docs/build/resources/builds.tsv header (18 tab-separated fields):
#     build_id status n_samples start_ts end_ts min_mem_kb max_mem_kb
#     mean_mem_kb p95_mem_kb min_cpu max_cpu mean_cpu p95_cpu min_load
#     max_load mean_load disk_rd_sec disk_wr_sec
#   Neither "verdict" nor "fingerprint" is a field name (whole-field match,
#   not a substring grep -- `grep -ci` over the whole 186-line file also
#   returns 0 for both literals, confirming no stray occurrence in the data
#   rows either). 185 data rows; `status` distribution: 179 KILLED / 5
#   UNKNOWN / 1 SUCCESS (matches specs/004-fast-dev-cycles/research.md RC-32:
#   "179 of 186 rows `KILLED` sampler status") -- so "KILLED" is the REAL,
#   dominant, currently-occurring sampler-status value the golden-bad fixture
#   below is modelled on, not a contrived string.
#   scripts/build_containerized.sh:400-415 confirms KILLED is written ONLY by
#   the `_build_res_emergency_stop` EXIT/INT/TERM/HUP trap when the
#   containerized-build SCRIPT itself was interrupted before its own
#   normal-path `stop --status SUCCESS|FAIL` call could run (line 405:
#   `--status "KILLED"`) -- i.e. KILLED is a claim about the SAMPLER
#   PROCESS's own lifecycle, never a claim about the artifact it was
#   watching.
#
# Verdict vocabulary (CLOSED, REUSED verbatim from
# specs/002-anti-slop-enforcement/contracts/gate-verdict.md and
# scripts/lib/critical_blocker_gate.sh's own CBG_RC_ALLOW=0/CBG_RC_FAIL=1/
# CBG_RC_REFUSE=4 -- §11.4.227 extend-don't-duplicate: T040 MUST NOT invent a
# second, parallel verdict vocabulary for build/deploy/QA events; plan.md
# T-A08's own Work text explicitly groups "build verdict" with the SAME
# critical_blocker_gate.sh-sourced "QA hand-off and QA verdict events"):
#   ALLOW | FAIL | REFUSE
#
# Artifact-fingerprint convention (REAL, measured against the live registry
# docs/requests/critical_blockers.jsonl, e.g. the real event line:
#   {"blocker_id":"*","event":"override","scope":"qa-deploy",
#    "fingerprint":"atmosphere-1.2.1-dev-0.2.8", ...}
# -- the project-prefixed release-tag string per §11.4.151, which is NOT the
# same identifier as builds.tsv's existing `build_id` column
# (`<git-short-hash>-<UTC timestamp>`, e.g. "0a12e7b60d6-20260515T044240Z",
# per scripts/build_containerized.sh:376-377 `git rev-parse --short HEAD`).
# T-A08's own Work text ("join ... rows to items via fingerprint") therefore
# requires ADDING a distinct `fingerprint` column to builds.tsv carrying this
# SAME release-tag-shaped string that scripts/flash.sh's post-verify step
# already reads back from the device as `ro.atmosphere.version`
# (scripts/lib/flashing.sh:362 -- currently logged only, never yet compared
# to anything) -- this is the join key the fixtures below are built around.
# Fixture fingerprints below are clearly test-marked
# ("atmosphere-0.0.0-test-T022-...") so they can never collide with a real
# release tag.
#
# Contract for T040 implementer (UNCONFIRMED: no
# specs/004-fast-dev-cycles/contracts/build-deploy-qa-events.md exists yet
# for T-A08; the CLI below is defined HERE, following the
# test_host_guard_red.sh precedent of a RED test defining a binding contract
# for its own later implementer, and is BINDING on T040):
#   Path       : constitution/scripts/fastcycle/cycle/build_deploy_qa_events.py
#                (constitution/scripts/fastcycle/cycle/ is presently
#                .gitkeep-only; T-A09's cycle_report.py lands alongside it and
#                reads its emitted rows, per plan.md T-A09 "commit/gate/
#                build/deploy/QA timing").
#   Executable : chmod +x with a `#!/usr/bin/env python3` shebang --
#                lib/triple_harness.sh invokes a non-executable --tool via
#                `sh "$tool"`, which would try to run Python source as a
#                POSIX shell script and fail; T040 MUST ship it executable.
#   Invocation : python3 build_deploy_qa_events.py <input-file>
#                (EXACTLY one positional arg, no subcommand -- verified
#                directly against lib/triple_harness.sh's own `run_tool`,
#                which invokes `"$tool" "$1"` with a single fixture-path
#                argument, line 151/152; a two-arg `check <input>` shape was
#                tried and rejected here after it produced a spurious
#                argv-usage exit 2 against a throwaway stub, confirming the
#                harness truly passes only one argument).
#   <input> is a JSON object whose "kind" field selects the record shape:
#     "build_event" : {"kind":"build_event","build_id":<str>,
#                       "status":<sampler status: SUCCESS|FAIL|UNKNOWN|KILLED>,
#                       "verdict":<str>,"fingerprint":<str>}
#     "join"        : {"kind":"join",
#                       "build":{"build_id":<str>,"status":<str>,
#                                "verdict":<str>,"fingerprint":<str>},
#                       "deploy":{"target_serial":<str>,"fingerprint":<str>,
#                                 "time":<ISO 8601 UTC>}}
#   Exit codes (kind=build_event):
#     0  verdict in {ALLOW,FAIL,REFUSE} -> stdout EXACTLY:
#          KIND=build_event
#          VERDICT=<verdict>
#     1  verdict absent/empty/not in {ALLOW,FAIL,REFUSE} -> stdout EXACTLY
#        one line naming the build_id and the value actually read
#        (§11.4.201(5) resolved evidence):
#          REFUSE build_id=<build_id> verdict_INVALID=<value>
#   Exit codes (kind=join):
#     0  build.verdict valid AND build.fingerprint == deploy.fingerprint ->
#        stdout EXACTLY:
#          KIND=join
#          FINGERPRINT=<fingerprint>
#          VERDICT=<verdict>
#          DEPLOY_TARGET=<target_serial>
#     1  invalid verdict, a missing/empty fingerprint on either side, a
#        fingerprint mismatch, or a missing/empty deploy target_serial ->
#        stdout EXACTLY one line naming build_id and the specific offending
#        reason, checked in this order: verdict_INVALID=<v> |
#        fingerprint_MISSING=<build|deploy|build,deploy> |
#        fingerprint_MISMATCH=<build-fp>/<deploy-fp> | target_serial_MISSING
#        (T048 restart round 1, R6-F1: both-absent / both-empty fingerprints
#        used to pass as an identity match; fixtures golden-bad-fp-* and
#        golden-bad-target-missing pin the refusal).
#   This tool is the pure, fixture-testable validate+join core. T040's own
#   emitter wiring into docs/build/resources/builds.tsv, scripts/flash.sh's
#   post-verify step, and scripts/lib/critical_blocker_gate.sh (plan.md T040,
#   conductor-only, SERIAL) is OUT OF SCOPE for this RED test and for T022.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test + its
# own fixtures under fixtures/build_deploy_qa/. It does NOT implement
# build_deploy_qa_events.py, does NOT edit docs/build/resources/builds.tsv,
# scripts/flash.sh, or scripts/lib/critical_blocker_gate.sh, and never
# invokes a real build, real flash, or real §11.4.236 QA gate -- every input
# exercised below is a fixture file under fixtures/build_deploy_qa/.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0).

HERE=$(cd "$(dirname "$0")" && pwd)
# FC_BDQ_TOOL_UNDER_TEST: the paired-mutation runner (test_fastcycle_r6_mutations.sh)
# points this at a MUTATED copy of the tool; every normal run uses the real file.
TOOL="${FC_BDQ_TOOL_UNDER_TEST:-$HERE/../cycle/build_deploy_qa_events.py}"
HARNESS="$HERE/lib/triple_harness.sh"
FIXDIR="$HERE/fixtures/build_deploy_qa"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T022 RED: build/deploy/QA verdict events (plan T-A08; FR-001, SC-001) =="

# =============================================================================
# Section A -- TODAY's real-data gap (no tool needed; measures the CURRENT,
# tracked project file, never a fixture).
# =============================================================================
# field_present <header-line> <field-name>: whole-tab-field exact match, never
# a substring grep (a future column "deployed_verdict_flag" must not be
# mistaken for "verdict").
field_present() {
    printf '%s\n' "$1" | awk -F'\t' -v want="$2" '
        { for (i = 1; i <= NF; i++) if ($i == want) found = 1 }
        END { exit(found ? 0 : 1) }'
}

# The consuming project's root is resolved via git's own submodule-awareness
# (constitution/ is itself a git submodule, so a bare `git rev-parse
# --show-toplevel` run from here would resolve to the SUBMODULE's own root,
# never the consuming project's) -- `--show-superproject-working-tree` is the
# git-native mechanism for exactly this, keeping this test project-agnostic
# per §11.4.28/§11.4.177 (it degrades to an honest SKIP, never a guess, when
# unavailable -- e.g. these scripts consumed standalone, outside any
# submodule checkout).
REPO_ROOT=$(git -C "$HERE" rev-parse --show-superproject-working-tree 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo "SKIP: cannot resolve the consuming project's root from $HERE (not inside a git submodule checkout) -- docs/build/resources/builds.tsv is consumer-project-specific (§11.4.35); Section A honestly skipped, not counted as pass or fail"
else
    REAL_BUILDS_TSV="$REPO_ROOT/docs/build/resources/builds.tsv"
    if [ ! -f "$REAL_BUILDS_TSV" ]; then
        echo "SKIP: $REAL_BUILDS_TSV not present in this checkout -- Section A honestly skipped"
    else
        HDR=$(head -n1 "$REAL_BUILDS_TSV")

        # Control needle (§11.4.273/§11.4.201(7)(b)): a KNOWN-PRESENT field
        # name must be found via the SAME exact-field-match mechanism used
        # for the real "verdict" check below, and a FABRICATED field name
        # must NOT be found -- else the extraction mechanism itself (not the
        # data) is blind, and that must be reported as such, never silently
        # read as "verdict is absent".
        if field_present "$HDR" "status"; then
            ok "control needle: known-present field 'status' found in builds.tsv header (extraction mechanism can see)"
        else
            bad "control needle BLIND: known-present field 'status' NOT found in builds.tsv header -- the field-extraction mechanism itself is broken, not the data; the absence-claim below is UNPROVEN"
        fi
        if field_present "$HDR" "__fc_t022_never_a_real_column__"; then
            bad "control needle BLIND: a FABRICATED field name was falsely reported present in builds.tsv header -- the field-extraction mechanism has a false-match defect"
        else
            ok "negative control: fabricated field name correctly absent from builds.tsv header"
        fi

        # The genuine RED assertion: builds.tsv MUST carry a "verdict" field.
        # It does not today (T-A08/T040 unimplemented) -- this is the real,
        # measured gap plan.md T-A08 exists to close.
        if field_present "$HDR" "verdict"; then
            ok "builds.tsv header carries a 'verdict' field (T-A08 has landed)"
        else
            bad "RED: builds.tsv header has NO 'verdict' field today (header: $HDR) -- every build row carries only the resource-sampler 'status' (SUCCESS|UNKNOWN|KILLED), never a build/QA verdict"
        fi

        # Realism check on the golden-bad fixture's modelled value: confirm
        # "KILLED" genuinely occurs in the real file today (research.md
        # RC-32), so the fixture below is not testing a contrived string.
        KILLED_N=$(awk -F'\t' 'NR > 1 && $2 == "KILLED" { c++ } END { print c + 0 }' "$REAL_BUILDS_TSV")
        TOTAL_N=$(awk -F'\t' 'NR > 1 { c++ } END { print c + 0 }' "$REAL_BUILDS_TSV")
        if [ "${KILLED_N:-0}" -gt 0 ]; then
            ok "realism check: $KILLED_N of $TOTAL_N real builds.tsv rows carry sampler status=KILLED (RC-32 confirmed live, not a contrived fixture value)"
        else
            bad "realism check FAILED: no real builds.tsv row carries status=KILLED today -- the golden-bad fixture below would then be modelling a status value that does not occur in real data"
        fi
    fi
fi

# =============================================================================
# Sections B/C/D -- golden-bad / golden(join) / negative-control, run through
# the shared C-005 self-validation-triple harness (lib/triple_harness.sh,
# T010). $TOOL is absent today (T-A08/T040 unimplemented), so the harness's
# very first check (`[ -f "$tool" ]`) fails and exits 2 before touching any
# fixture -- the expected RED outcome for all three, reported as three
# separately-named FAILs below so each of the task's checks is individually
# visible (never collapsed into one opaque "harness rc=2" line).
# =============================================================================
# Invoked as `sh "$HARNESS"` below (never as a bare `"$HARNESS"`), so only
# file PRESENCE matters here, not its execute bit (an earlier `-x` check here
# was a self-inflicted instrument bug -- triple_harness.sh is tracked without
# the execute bit set, and `sh <path>` does not require one; §11.4.273).
if [ ! -f "$HARNESS" ]; then
    bad "lib/triple_harness.sh not found at $HARNESS -- cannot run the self-validation triple"
else
    HOUT=$(sh "$HARNESS" --tool "$TOOL" --fixtures "$FIXDIR" 2>&1); HRC=$?
    echo "---- lib/triple_harness.sh output (rc=$HRC) ----"
    printf '%s\n' "$HOUT"
    echo "---- end lib/triple_harness.sh output ----"

    if [ ! -f "$TOOL" ]; then
        bad "RED: golden-bad (a KILLED sampler status is refused as a build verdict) -- $TOOL is absent, cannot run the check (harness rc=$HRC)"
        bad "RED: golden (a build + flash fixture yields verdict and deploy rows joined by artifact fingerprint) -- $TOOL is absent, cannot run the check (harness rc=$HRC)"
        bad "RED: negative-control (status=KILLED with a genuinely-valid distinct verdict must NOT be refused) -- $TOOL is absent, cannot run the check (harness rc=$HRC)"
    else
        # Once T040 lands, $TOOL exists and the harness prints ONE JSON line per
        # fixture class. T048 restart round 1 (R6-F2): the earlier check was
        # `grep '"class":"golden-bad".*"ok":true'`, which (a) also matched any
        # golden-bad-* line and (b) never looked at the harness exit status, so a
        # failing extra class could hide behind a passing one. Now every class is
        # checked by its EXACT name, the class list is closed (a fixture directory
        # deleted or renamed is a FAIL, never a silent loss of coverage), and the
        # harness exit status must be 0.
        class_ok() {
            printf '%s\n' "$HOUT" | grep -q "\"class\":\"$1\",\"expected\":\"[01]\",\"fixture\":\"$1\",\"ok\":true}"
        }
        check_class() { # <class> <description>
            if [ ! -d "$FIXDIR/$1" ]; then
                bad "$1: fixture directory $FIXDIR/$1 is missing -- this coverage was silently dropped"
            elif class_ok "$1"; then
                ok "$1: $2"
            else
                bad "$1: NOT handled correctly -- $2 (see harness output above)"
            fi
        }
        check_class golden-bad "a KILLED sampler status is refused as a build verdict"
        check_class golden-good "a build + flash fixture yields verdict and deploy rows joined by artifact fingerprint"
        check_class negative-control "status=KILLED with a genuinely-valid distinct verdict is correctly NOT refused"
        # R6-F1/F2: the join's identity check must be able to FAIL.
        check_class golden-bad-fp-mismatch "a build/deploy fingerprint MISMATCH is refused and both values are named"
        check_class golden-bad-fp-missing-both "a join with NO fingerprint on either side is refused (None == None is not an identity match)"
        check_class golden-bad-fp-empty-both "a join with EMPTY fingerprints on both sides is refused (\"\" == \"\" is not an identity match)"
        check_class golden-bad-fp-missing-deploy "a join whose deploy side has no fingerprint is refused"
        check_class golden-bad-target-missing "a join with no deploy target_serial is refused (DEPLOY_TARGET=None is not a deploy record)"
        check_class golden-bad-join-verdict-invalid "a join whose build verdict is the sampler status KILLED is refused"
        if [ "$HRC" -eq 0 ]; then
            ok "harness exit status 0 (every fixture class as expected)"
        else
            bad "harness exit status $HRC (non-zero: a fixture class mismatched or the tool errored)"
        fi
        # Closed class list: an extra golden-bad-* directory nobody checks above is
        # a coverage claim with no assertion behind it.
        for d in "$FIXDIR"/golden-bad-*; do
            [ -d "$d" ] || continue
            case ${d##*/} in
                golden-bad-fp-mismatch|golden-bad-fp-missing-both|golden-bad-fp-empty-both|golden-bad-fp-missing-deploy|golden-bad-target-missing|golden-bad-join-verdict-invalid) ;;
                *) bad "unlisted fixture class ${d##*/} -- add it to the closed check list in this test" ;;
            esac
        done
    fi
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
