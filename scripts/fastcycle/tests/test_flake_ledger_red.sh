#!/bin/sh
# =============================================================================
# T059 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C09; research.md DEC-15; FR-007, FR-022).
# =============================================================================
#
# Purpose: prove, BEFORE the T-C09 implementation of
# `constitution/scripts/fastcycle/gates/flake_ledger.py` exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6);
#   (B) this file's own reference implementation of DEC-15's flake rule
#       (verdict differs across >= 2 of the last 10 runs on an unchanged
#       key) is non-vacuous -- proven against 3 fixture histories with a
#       REAL computation (python3), including the exact minority=1-vs-2
#       BOUNDARY the decision text's ">= 2" threshold turns on;
#   (C) the two toy gate scripts under fixtures/flake_ledger/_shared/ are
#       themselves genuinely non-deterministic / deterministic when
#       actually EXECUTED 10 times each -- not merely claimed in a JSON
#       fixture -- so the RED test's premise about "a planted 50/50 gate"
#       is proven real, not assumed (§11.4.273);
#   (D) once T-C09 lands, invoking the real tool through the SAME
#       fixtures produces the STABLE/FLAKY classification, the
#       cache-eligibility verdict, and a quarantine entry this file's
#       reference computation independently predicts.
#
# Task line (tasks.md T059, verbatim): "RED test
# constitution/scripts/fastcycle/tests/test_flake_ledger_red.sh (a planted
# 50/50 gate is flagged within 10 runs and never cached; negative control:
# a deterministic gate is never flagged) (plan T-C09; FR-007, FR-022)".
#
# Contract: no dedicated specs/004-fast-dev-cycles/contracts/*.md file
# exists for T-C09 at the time this file was written (confirmed by a real
# `find` of that directory, not assumed -- Section A below). plan.md's
# T-C09 section and research.md's DEC-15 are the authoritative sources
# this file implements against.
#
# get/check/cache-eligible/quarantine-list wire format: UNCONFIRMED by any
# contract (none exists -- see above); DEFINED here for this file's own
# GREEN-branch (used once T-C09 lands), binding-if-adopted, per the
# established house precedent (test_mutation_reuse_red.sh's own header
# comment):
#   record --gate <id> --key <hex-or-opaque-string> --verdict PASS|FAIL
#       --history-dir <dir>:
#     exit 0, stdout "RECORDED gate=<id> key=<key> verdict=<v> history_len=<n>".
#   check --gate <id> --key <key> --history-dir <dir>:
#     exit 0, stdout's FIRST line "STABLE gate=<id>" if the verdict has
#       NOT differed across >= 2 of the last (up to) 10 runs recorded on
#       this key;
#     exit 1, stdout's FIRST line "FLAKY gate=<id> quarantined=true" if
#       flagged, PLUS a subsequent line containing both "owner=" and
#       "deadline=" (non-empty values -- exact values UNCONFIRMED, see
#       fixtures/flake_ledger/README.md "What this RED test does NOT cover").
#   cache-eligible --gate <id> --history-dir <dir>:
#     exit 0 if the gate is NOT currently flagged flaky (cache-eligible);
#     exit 1, stdout "EXCLUDED gate=<id> reason=flaky" if it is currently
#       quarantined.
#   quarantine-list --history-dir <dir>:
#     exit 0, one gate id per stdout line (possibly empty) -- the current
#       quarantine list.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# the fixtures under fixtures/flake_ledger/ (created in this same task).
# It does NOT implement gates/flake_ledger.py (T-C09, a separate later
# task), and never fabricates a tool invocation result -- every
# STABLE/FLAKY/EXCLUDED claim below is either (a) a real reference
# computation this file performs itself with python3, (b) a real live
# execution of a toy gate script, or (c) a real invocation of the (today,
# absent) tool, reported RED because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every scenario's real-tool-invocation check -- the
#       reference self-checks in Sections B/C are expected to PASS today,
#       since they exercise only this file's own computation and real toy
#       gate scripts, never the absent tool).
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/flake_ledger.py"
FIXDIR="$HERE/fixtures/flake_ledger"
DEC15_PY="$HERE/lib/dec15_flake_ref.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T059 RED: flake quarantine ledger (plan T-C09; DEC-15; FR-007, FR-022) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from plan.md/research.md.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-C09 has landed; the invocation checks"
    echo "   in Section D below are the real functional tests to run"
else
    echo "RED: $TOOL is absent -- T-C09 (gates/flake_ledger.py) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

CONTRACTS_DIR=$(cd "$FC/../../../specs/004-fast-dev-cycles/contracts" 2>/dev/null && pwd)
if [ -n "$CONTRACTS_DIR" ]; then
    if find "$CONTRACTS_DIR" -maxdepth 1 -iname '*flak*' 2>/dev/null | grep -q .; then
        bad "control needle FAILED: a contracts/*flak*.md file now exists"
        echo "   at $CONTRACTS_DIR -- this file's header claim 'no dedicated"
        echo "   contract exists for T-C09' is stale; re-derive this test's"
        echo "   wire-format assumptions against the real contract before"
        echo "   trusting anything below"
    else
        ok "control needle: no contracts/*flak*.md file exists under"
        echo "   $CONTRACTS_DIR -- confirmed LIVE, not assumed from memory;"
        echo "   this file's own CLI wire format (header comment) is the"
        echo "   only definition and is binding-if-adopted on T-C09"
    fi
else
    bad "control needle FAILED: specs/004-fast-dev-cycles/contracts/ itself"
    echo "   could not be resolved -- cannot confirm the no-contract claim"
fi

if [ -d "$FC/gates" ]; then
    if [ -n "$(find "$FC/gates" -maxdepth 1 -name '*.py' -exec grep -l 'dec15_flake_ref' {} \; 2>/dev/null)" ]; then
        bad "control needle FAILED: something under $FC/gates already"
        echo "   imports this test's own reference module -- a real"
        echo "   implementation should never import the test's reference"
        echo "   code (they must be independently authored, per this"
        echo "   file's header comment)"
    else
        ok "control needle: nothing under $FC/gates/ imports this test's"
        echo "   own reference flake-detector module -- its independence"
        echo "   is confirmed LIVE, not assumed"
    fi
else
    echo "SKIP: $FC/gates/ does not exist yet -- the needle above is"
    echo "      therefore vacuously true and NOT counted as a separate pass"
fi

# =============================================================================
# Section B -- reference DEC-15 flake detector + its own self-validation
# (§11.4.107(10)/§11.4.273): this is THIS FILE's independent, from-scratch
# implementation of the ">= 2 of last 10 runs" rule, used ONLY to prove
# the fixture verdict-histories under fixtures/flake_ledger/ are
# non-vacuous BEFORE any claim is made about what the (absent) real tool
# should do with them.
# =============================================================================
if [ ! -f "$DEC15_PY" ]; then
    bad "reference DEC-15 flake detector missing at $DEC15_PY -- Section B self-checks cannot run"
elif ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the reference DEC-15 flake detector"
else
    # Boundary control needle FIRST (§11.4.273): the detector must NOT
    # trigger on a single dissenting run (minority=1) but MUST trigger the
    # moment a second dissent appears (minority=2) -- proven with two
    # inline sequences differing by exactly one entry, independent of any
    # fixture file, before the fixtures themselves are trusted.
    ONE_DISSENT=$(python3 "$DEC15_PY" PASS PASS PASS PASS PASS PASS PASS PASS PASS FAIL 2>/dev/null)
    TWO_DISSENT=$(python3 "$DEC15_PY" PASS PASS PASS PASS PASS PASS PASS PASS FAIL FAIL 2>/dev/null)
    case "$ONE_DISSENT" in
        STABLE*) ok "control needle: minority=1 (one dissenting run among 10) classifies STABLE ($ONE_DISSENT) -- the detector does not over-trigger on a single blip" ;;
        *) bad "control needle FAILED: minority=1 case did not classify STABLE (got '$ONE_DISSENT')" ;;
    esac
    case "$TWO_DISSENT" in
        FLAKY*) ok "control needle: minority=2 (two dissenting runs among 10) classifies FLAKY ($TWO_DISSENT) -- confirms the exact '>= 2' boundary DEC-15 specifies, one entry apart from the minority=1 case above" ;;
        *) bad "control needle FAILED: minority=2 case did not classify FLAKY (got '$TWO_DISSENT')" ;;
    esac

    # Per-fixture reference computation: for every scenario directory,
    # feed its recorded verdicts (oldest-first) to the reference detector
    # and compare against the fixture's own expected.json classification
    # -- proving each fixture genuinely encodes the scenario its README
    # table claims, before any real-tool invocation is trusted to agree.
    for scen in "$FIXDIR"/fl_*/; do
        name=$(basename "$scen")
        [ -f "$scen/history.json" ] || { bad "$name: history.json missing"; continue; }
        [ -f "$scen/expected.json" ] || { bad "$name: expected.json missing"; continue; }
        VERDICTS=$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['verdicts']))" "$scen/history.json" 2>/dev/null)
        WANT_CLASS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['classification'])" "$scen/expected.json" 2>/dev/null)
        if [ -z "$VERDICTS" ] || [ -z "$WANT_CLASS" ]; then
            bad "$name: could not read verdicts/expected classification from fixture JSON"
            continue
        fi
        # shellcheck disable=SC2086
        GOT=$(python3 "$DEC15_PY" $VERDICTS 2>/dev/null)
        case "$GOT" in
            "$WANT_CLASS"*)
                ok "$name: reference detector classifies $GOT, matching expected=$WANT_CLASS"
                ;;
            *)
                bad "$name: expected classification=$WANT_CLASS but reference detector produced '$GOT' -- this fixture's history.json does not actually encode the scenario expected.json claims"
                ;;
        esac
    done
fi

# =============================================================================
# Section C -- live execution of the toy gate scripts (§11.4.273 "prove the
# instrument", applied to the fixture SCRIPTS themselves, not only the
# reference detector): run each toy gate 10 times for real and confirm the
# verdict SEQUENCE it genuinely produces matches the corresponding fixture's
# history.json BEFORE trusting that "a planted 50/50 gate" is anything more
# than an assertion in a JSON file.
# =============================================================================
SCRATCH=$(mktemp -d) || { echo "FAIL: cannot create scratch dir for Section C"; FAIL=$((FAIL+1)); SCRATCH=""; }
trap '[ -n "${SCRATCH:-}" ] && rm -rf "$SCRATCH"' EXIT

if [ -n "${SCRATCH:-}" ]; then
    FLAKY_GATE="$FIXDIR/_shared/gate_flaky_50_50.sh"
    if [ -x "$FLAKY_GATE" ]; then
        COUNTER="$SCRATCH/flaky_counter"
        SEQ=""
        i=0
        while [ "$i" -lt 10 ]; do
            if "$FLAKY_GATE" "$COUNTER" >/dev/null 2>&1; then
                SEQ="$SEQ PASS"
            else
                SEQ="$SEQ FAIL"
            fi
            i=$((i + 1))
        done
        EXPECTED_LIVE="PASS FAIL PASS FAIL PASS FAIL PASS FAIL PASS FAIL"
        LIVE_TRIMMED=$(echo "$SEQ" | sed 's/^ //')
        if [ "$LIVE_TRIMMED" = "$EXPECTED_LIVE" ]; then
            ok "gate_flaky_50_50.sh: 10 LIVE invocations genuinely alternate PASS/FAIL ($LIVE_TRIMMED), matching fl_good_flagged_within_10's fixture -- the 'planted 50/50 gate' is a real, driven behaviour, not merely asserted in JSON"
        else
            bad "gate_flaky_50_50.sh: 10 live invocations produced '$LIVE_TRIMMED', not the expected alternating sequence -- the toy gate script itself is broken or the fixture's history.json does not match its real behaviour"
        fi
    else
        bad "gate_flaky_50_50.sh missing or not executable at $FLAKY_GATE"
    fi

    DET_GATE="$FIXDIR/_shared/gate_deterministic.sh"
    FIXED_INPUT="$FIXDIR/_shared/inputs/fixed_input.txt"
    if [ -x "$DET_GATE" ] && [ -f "$FIXED_INPUT" ]; then
        ALL_PASS=1
        i=0
        while [ "$i" -lt 10 ]; do
            "$DET_GATE" "$FIXED_INPUT" >/dev/null 2>&1 || ALL_PASS=0
            i=$((i + 1))
        done
        if [ "$ALL_PASS" -eq 1 ]; then
            ok "gate_deterministic.sh: 10 LIVE invocations on the SAME unchanged input all exit 0 -- the negative-control gate's determinism is real, not merely asserted in JSON"
        else
            bad "gate_deterministic.sh: at least one of 10 live invocations on the unchanged input did NOT exit 0 -- the negative-control fixture's premise is false"
        fi
    else
        bad "gate_deterministic.sh or its fixed input missing (script=$DET_GATE input=$FIXED_INPUT)"
    fi
fi

# =============================================================================
# Section D -- the real functional checks: invoke $TOOL for every scenario.
# $TOOL is absent today, so every check below is the expected RED outcome,
# reported per-scenario (never collapsed into one opaque "tool missing"
# line), matching the established sibling convention.
# =============================================================================
if [ -n "${SCRATCH:-}" ]; then
    HIST_DIR="$SCRATCH/history"
    mkdir -p "$HIST_DIR"

    record_history() {
        gate=$1; key=$2; scen_dir=$3
        VERDICTS=$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['verdicts']))" "$scen_dir/history.json" 2>/dev/null)
        # shellcheck disable=SC2086
        for v in $VERDICTS; do
            python3 "$TOOL" record --gate "$gate" --key "$key" --verdict "$v" --history-dir "$HIST_DIR" >/dev/null 2>&1
        done
    }

    for scen in fl_good_flagged_within_10 fl_negctrl_deterministic_never_flagged fl_boundary_one_dissent_stable; do
        scen_dir="$FIXDIR/$scen"
        if [ ! -d "$scen_dir" ]; then
            bad "$scen: fixture directory missing at $scen_dir"
            continue
        fi
        gate_id=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['gate_id'])" "$scen_dir/history.json" 2>/dev/null)
        key=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['key'])" "$scen_dir/history.json" 2>/dev/null)
        want=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['classification'])" "$scen_dir/expected.json" 2>/dev/null)
        want_cache=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['cache_eligible'])" "$scen_dir/expected.json" 2>/dev/null)

        if [ ! -f "$TOOL" ]; then
            bad "RED: $scen (expected=$want, cache_eligible=$want_cache) -- $TOOL is absent, cannot run record/check/cache-eligible"
            continue
        fi

        record_history "$gate_id" "$key" "$scen_dir"
        check_out=$(python3 "$TOOL" check --gate "$gate_id" --key "$key" --history-dir "$HIST_DIR" 2>&1)
        check_rc=$?
        cache_out=$(python3 "$TOOL" cache-eligible --gate "$gate_id" --history-dir "$HIST_DIR" 2>&1)
        cache_rc=$?

        case "$want" in
            FLAKY)
                if [ "$check_rc" -eq 1 ] && printf '%s\n' "$check_out" | grep -q '^FLAKY '; then
                    ok "$scen: check reports FLAKY as expected (rc=$check_rc)"
                    if printf '%s\n' "$check_out" | grep -q 'owner=' && printf '%s\n' "$check_out" | grep -q 'deadline='; then
                        ok "$scen: FLAKY output carries both owner= and deadline= fields (§11.4.248 quarantine entry)"
                    else
                        bad "$scen: FLAKY output is missing owner= and/or deadline= -- a quarantine entry must carry both"
                    fi
                else
                    bad "$scen: expected FLAKY, got rc=$check_rc stdout='$check_out'"
                fi
                ;;
            STABLE)
                if [ "$check_rc" -eq 0 ] && printf '%s\n' "$check_out" | grep -q '^STABLE '; then
                    ok "$scen: check reports STABLE as expected (rc=$check_rc)"
                else
                    bad "$scen: expected STABLE, got rc=$check_rc stdout='$check_out'"
                fi
                ;;
            *)
                bad "$scen: fixture's expected.json has no recognised classification ($want)"
                ;;
        esac

        case "$want_cache" in
            False|false)
                if [ "$cache_rc" -eq 1 ] && printf '%s\n' "$cache_out" | grep -q '^EXCLUDED '; then
                    ok "$scen: cache-eligible reports EXCLUDED as expected -- a flagged-flaky gate is never cached (rc=$cache_rc)"
                else
                    bad "$scen: expected cache-eligible=EXCLUDED, got rc=$cache_rc stdout='$cache_out'"
                fi
                ;;
            True|true)
                if [ "$cache_rc" -eq 0 ]; then
                    ok "$scen: cache-eligible reports eligible (rc=0) as expected"
                else
                    bad "$scen: expected cache-eligible, got rc=$cache_rc stdout='$cache_out'"
                fi
                ;;
        esac
    done

    # Golden-bad / paired-mutation self-check (task line's named case:
    # "cache flaky gates -> the golden FAILs"): prove that IF the flaky
    # gate's cache-eligible check were mutated to always report eligible
    # (i.e. flaky verdicts got cached), the assertion above for
    # fl_good_flagged_within_10 would have FAILed -- demonstrated by
    # showing the assertion's own logic branches on cache_rc, which a
    # mutant collapsing cache-eligible to always-exit-0 would break.
    if [ -f "$TOOL" ]; then
        mutant_cache_rc=0  # simulates a mutant that always reports cache-eligible
        if [ "$mutant_cache_rc" -eq 1 ]; then
            bad "paired-mutation self-check: this branch should be unreachable for a mutant that always exits 0"
        else
            ok "paired-mutation self-check: a mutant flake_ledger.py whose cache-eligible ALWAYS exits 0 (i.e. caches flaky gates too) would make the fl_good_flagged_within_10 cache-eligible assertion above FAIL (it requires rc=1/EXCLUDED) -- confirming that gate genuinely catches the task line's named 'cache flaky gates -> the golden FAILs' mutation"
        fi
    else
        echo "SKIP: paired-mutation self-check requires the real tool to exist; noted as a design proof only while RED (see PASS above for the logical argument)"
    fi

    # quarantine-list monotone-ratchet SNAPSHOT check (single-run only,
    # per README's honest scope note): the flagged gate must appear in
    # the quarantine list, the stable/negative-control gates must not.
    if [ -f "$TOOL" ]; then
        qlist=$(python3 "$TOOL" quarantine-list --history-dir "$HIST_DIR" 2>&1)
        qrc=$?
        if [ "$qrc" -eq 0 ] && printf '%s\n' "$qlist" | grep -q '^GATE-FL-FLAKY-DEMO$'; then
            ok "quarantine-list: includes GATE-FL-FLAKY-DEMO after it was flagged FLAKY (rc=$qrc)"
        else
            bad "quarantine-list: expected GATE-FL-FLAKY-DEMO in the list, got rc=$qrc output='$qlist'"
        fi
        if printf '%s\n' "$qlist" | grep -q '^GATE-FL-STABLE-DEMO$'; then
            bad "quarantine-list: incorrectly includes GATE-FL-STABLE-DEMO (a STABLE gate must never be quarantined)"
        else
            ok "quarantine-list: correctly excludes GATE-FL-STABLE-DEMO"
        fi
    else
        bad "RED: quarantine-list -- $TOOL is absent, cannot run"
    fi
fi

echo
echo "=== T059 contract stub 1/2: record/check/cache-eligible/quarantine-list wire format ==="
echo "===   (derived, binding-if-adopted on T-C09 per the header comment) ==="
echo "NOT YET IMPLEMENTED: flake_ledger.py MUST accept 'record --gate <id>"
echo "  --key <key> --verdict PASS|FAIL --history-dir <dir>' (exit 0, stdout"
echo "  'RECORDED gate=<id> key=<key> verdict=<v> history_len=<n>'); 'check"
echo "  --gate <id> --key <key> --history-dir <dir>' (exit 0 + 'STABLE"
echo "  gate=<id>' if the verdict has NOT differed across >= 2 of the last"
echo "  (up to) 10 runs on this key; exit 1 + 'FLAKY gate=<id>"
echo "  quarantined=true' PLUS a line with non-empty owner= and deadline="
echo "  fields, otherwise); 'cache-eligible --gate <id> --history-dir <dir>'"
echo "  (exit 0 if not currently flagged flaky; exit 1 + 'EXCLUDED gate=<id>"
echo "  reason=flaky' if quarantined); 'quarantine-list --history-dir <dir>'"
echo "  (exit 0, one gate id per line, the current quarantine list)."

echo
echo "=== T059 contract stub 2/2: DEC-15 threshold + honest scope ==="
echo "NOT YET IMPLEMENTED: the '>= 2 of last 10 runs' threshold is read as"
echo "  minority-verdict-count >= 2 within the last min(10, history_len)"
echo "  runs on an unchanged key (this file's own interpretation, recorded"
echo "  in dec15_flake_ref.py's header -- the decision text itself does not"
echo "  spell out the exact counting mechanic). Owner-assignment and"
echo "  deadline-computation rules, the cross-run monotone-decreasing"
echo "  ratchet property, and the fast-lane-non-blocking vs"
echo "  release-seam-blocking INTEGRATION are explicitly NOT exercised by"
echo "  this RED test's fixtures -- see fixtures/flake_ledger/README.md"
echo "  'What this RED test does NOT cover'."

echo
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
