#!/bin/sh
# =============================================================================
# T057 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C07; FR-006, FR-007, SC-002).
# =============================================================================
#
# Purpose: prove, BEFORE the T-C07 implementation of
# `constitution/scripts/fastcycle/gates/mutation_reuse.py` exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed — §11.4.6);
#   (B) this file's own reference implementation of the DEC-23 cache-key
#       formula (hash(patch || gate script || observed inputs || tool
#       versions)) is non-vacuous — changing exactly one of the 4 key
#       components really does change the reference digest, and leaving
#       every component byte-identical really does leave it unchanged —
#       proven by REAL sha256 computation (python3 hashlib), never merely
#       asserted (§11.4.273);
#   (C) this file's own reference implementation of DEC-23's
#       comment/whitespace normalisation rule (for the trivial-equivalence
#       mutant-dedup half) genuinely collapses two differently-formatted
#       but semantically-identical scripts to the same digest, and does
#       NOT collapse two genuinely different scripts;
#   (D) once T-C07 lands, invoking the real tool through the SAME fixtures
#       produces the outcome (`HIT`/`MISS`/`DUPLICATE`/`DISTINCT`) this
#       file's reference computations independently predict, for every one
#       of the 9 scenarios under fixtures/mutation_reuse/ (see that
#       directory's own README.md for the full scenario table).
#
# Contract: no dedicated specs/004-fast-dev-cycles/contracts/*.md file
# exists for T-C07 at the time this file was written (confirmed by a real
# `ls` of that directory, not assumed — Section A below). plan.md's T-C07
# section (Work / Protecting-tests / Origin) and research.md's DEC-23 are
# the authoritative sources this file implements against.
#
# Task line (tasks.md T057, verbatim): "RED test
# constitution/scripts/fastcycle/tests/test_mutation_reuse_red.sh (changing
# one gate input re-runs that gate's mutations; golden-bad: a SURVIVED
# verdict offered for reuse is refused; control needle: a tampered gate
# input re-runs its mutation; byte-identical normalised mutated scripts are
# reported as duplicates, not run twice)".
#
# get/put/check-duplicate wire format: UNCONFIRMED by any contract (none
# exists — see above); DEFINED here for this file's own GREEN-branch (used
# once T-C07 lands), binding-if-adopted, per the established house
# precedent (test_verdict_cache_red.sh's own header comment):
#   put <cache-dir> --gate <id> --mutation-id <id> --patch <diff>
#       --gate-script <path> --inputs <envelope.json> --verdict
#       KILLED|SURVIVED --evidence <path>:
#     exit 0, stdout "PUT key=<hex64> verdict=<v>" — a SURVIVED verdict MAY
#     be refused at put-time (any nonzero exit) OR MAY be silently accepted
#     without becoming servable — EITHER is accepted by this file; the
#     load-bearing assertion is the SUBSEQUENT get() reporting MISS
#     regardless (mr_bad_survived_never_reused/).
#   get <cache-dir> --gate <id> --mutation-id <id> --patch <diff>
#       --gate-script <path> --inputs <envelope.json>:
#     HIT:  exit 0, stdout's FIRST line "HIT key=<hex64> verdict=KILLED"
#           (a HIT's stdout MUST NOT contain "verdict=SURVIVED" — SURVIVED
#           is never servable, per DEC-23).
#     MISS: exit 1, stdout's FIRST line "MISS key=<hex64>" (or
#           key=UNKNOWN when the key cannot be computed).
#   check-duplicate --script-a <path> --script-b <path>:
#     exit 0, stdout "DUPLICATE norm_sha=<hex64>" if the two scripts
#     normalise to the same digest; exit 1, stdout "DISTINCT" otherwise.
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# the fixtures under fixtures/mutation_reuse/ (created in this same task).
# It does NOT implement gates/mutation_reuse.py (T-C07, a separate later
# task), and never fabricates a tool invocation result — every HIT/MISS/
# DUPLICATE/DISTINCT claim below is either (a) a real reference computation
# this file performs itself with python3 hashlib, or (b) a real invocation
# of the (today, absent) tool, reported RED because the tool cannot be
# found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0
#       for every scenario's real-tool-invocation check — the reference
#       self-checks in Sections B/C are expected to PASS today, since they
#       exercise only this file's own computation, not the absent tool).
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/mutation_reuse.py"
FIXDIR="$HERE/fixtures/mutation_reuse"
DEC23_PY="$HERE/lib/dec23_key_ref.py"
TCE_PY="$HERE/lib/tce_normalize_ref.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T057 RED: sound mutation reuse + TCE dedup (plan T-C07; FR-006, FR-007, SC-002) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from plan.md/research.md.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-C07 has landed; the invocation checks"
    echo "   in Section D below are the real functional tests to run"
else
    echo "RED: $TOOL is absent -- T-C07 (gates/mutation_reuse.py) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

CONTRACTS_DIR=$(cd "$FC/../../../specs/004-fast-dev-cycles/contracts" 2>/dev/null && pwd)
if [ -n "$CONTRACTS_DIR" ]; then
    if find "$CONTRACTS_DIR" -maxdepth 1 -iname '*mutat*' 2>/dev/null | grep -q .; then
        bad "control needle FAILED: a contracts/*mutat*.md file now exists"
        echo "   at $CONTRACTS_DIR -- this file's header claim 'no dedicated"
        echo "   contract exists for T-C07' is stale; re-derive this test's"
        echo "   wire-format assumptions against the real contract before"
        echo "   trusting anything below"
    else
        ok "control needle: no contracts/*mutat*.md file exists under"
        echo "   $CONTRACTS_DIR -- confirmed LIVE, not assumed from memory;"
        echo "   this file's own CLI wire format (header comment) is the"
        echo "   only definition and is binding-if-adopted on T-C07"
    fi
else
    bad "control needle FAILED: specs/004-fast-dev-cycles/contracts/ itself"
    echo "   could not be resolved -- cannot confirm the no-contract claim"
fi

if [ -d "$FC/gates" ]; then
    if [ -n "$(find "$FC/gates" -maxdepth 1 -name '*.py' -exec grep -l 'dec23_key_ref\|tce_normalize_ref' {} \; 2>/dev/null)" ]; then
        bad "control needle FAILED: something under $FC/gates already"
        echo "   imports this test's own reference modules -- a real"
        echo "   implementation should never import the test's reference"
        echo "   code (they must be independently authored, per this"
        echo "   file's header comment)"
    else
        ok "control needle: nothing under $FC/gates/ imports this test's"
        echo "   own reference key/normaliser modules -- their independence"
        echo "   is confirmed LIVE, not assumed"
    fi
else
    echo "SKIP: $FC/gates/ does not exist yet -- the needle above is"
    echo "      therefore vacuously true and NOT counted as a separate pass"
fi

# =============================================================================
# Section B -- reference DEC-23 key builder + its own self-validation
# (§11.4.107(10)/§11.4.273): this is THIS FILE's independent, from-scratch
# implementation of the 4-component DEC-23 formula, used ONLY to prove the
# fixture pairs under fixtures/mutation_reuse/ are non-vacuous BEFORE any
# claim is made about what the (absent) real tool should do with them.
# =============================================================================
if [ ! -f "$DEC23_PY" ]; then
    bad "reference DEC-23 key builder missing at $DEC23_PY -- Section B self-checks cannot run"
elif ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the reference DEC-23 key builder"
else
    K1=$(python3 "$DEC23_PY" "$FIXDIR/mr_good_killed_reuse/put_envelope.json" 2>/dev/null)
    if [ -z "$K1" ]; then
        bad "reference key builder produced no output on mr_good_killed_reuse/put_envelope.json"
    else
        ok "reference DEC-23 key builder runs and produces a key ($K1)"
    fi

    # Self-validation of the reference builder itself, BEFORE trusting it to
    # judge any fixture: two structurally-identical envelopes differing
    # only in JSON key ORDER must yield the SAME key (a builder that
    # (bug) hashed raw dict-insertion order for tool_versions instead of a
    # canonical sorted form would produce a DIFFERENT key here).
    REORDER_JSON=$(mktemp)
    python3 - "$FIXDIR/mr_good_killed_reuse/put_envelope.json" "$REORDER_JSON" <<'PYEOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    env = json.load(f)
reordered = {
    "tool_versions": dict(reversed(list(env["tool_versions"].items()))),
    "observed_inputs": env["observed_inputs"],
    "gate_script_sha256": env["gate_script_sha256"],
    "patch_sha256": env["patch_sha256"],
    "verdict": env["verdict"],
    "mutation_id": env["mutation_id"],
    "gate_id": env["gate_id"],
}
with open(dst, "w") as f:
    json.dump(reordered, f)
PYEOF
    K1_REORDERED=$(python3 "$DEC23_PY" "$REORDER_JSON" 2>/dev/null)
    if [ -n "$K1" ] && [ "$K1" = "$K1_REORDERED" ]; then
        ok "control needle: reordering tool_versions' JSON keys does not change the reference key ($K1) -- the builder canonicalises order, it does not accidentally hash it"
    else
        bad "control needle FAILED: reordering tool_versions changed the reference key (original=$K1 reordered=$K1_REORDERED) -- dec23_key_ref.py leaks non-semantic JSON ordering into the key"
    fi
    rm -f "$REORDER_JSON"

    # -------------------------------------------------------------------
    # Per-scenario reference computation: for every cache-behavior fixture
    # directory, compute the reference key of BOTH envelopes and check
    # (put_key == get_key) against the scenario's expected HIT/MISS --
    # EXCEPT mr_bad_survived_never_reused, whose keys legitimately MATCH
    # (asserted separately below, by name, exactly as T051's
    # vc_admission_skip_never_cached is) since its expected MISS comes from
    # the SURVIVED-never-reused rule, not from a key mismatch.
    # -------------------------------------------------------------------
    for scen in "$FIXDIR"/*/; do
        name=$(basename "$scen")
        case "$name" in
            mr_tce_duplicate|mr_tce_distinct) continue ;;
            mr_bad_survived_never_reused) continue ;;
        esac
        [ -f "$scen/put_envelope.json" ] || continue
        [ -f "$scen/get_envelope.json" ] || continue
        [ -f "$scen/expected" ] || continue
        want=$(head -n1 "$scen/expected" | tr -d '\r\n')
        case "$want" in
            HIT|MISS) : ;;
            *) bad "$name: expected file's first line is '$want', not HIT/MISS"; continue ;;
        esac
        put_key=$(python3 "$DEC23_PY" "$scen/put_envelope.json" 2>/dev/null)
        get_key=$(python3 "$DEC23_PY" "$scen/get_envelope.json" 2>/dev/null)
        if [ -z "$put_key" ] || [ -z "$get_key" ]; then
            bad "$name: reference key builder failed to compute a key from one of the envelopes"
            continue
        fi
        if [ "$want" = HIT ]; then
            if [ "$put_key" = "$get_key" ]; then
                ok "$name: reference keys of put/get envelopes are IDENTICAL ($put_key), matching expected=HIT"
            else
                bad "$name: expected=HIT but reference keys DIFFER (put=$put_key get=$get_key) -- this fixture pair does not actually encode the scenario its README claims"
            fi
        else
            if [ "$put_key" != "$get_key" ]; then
                ok "$name: reference keys of put/get envelopes DIFFER (put=$put_key get=$get_key), matching expected=MISS"
            else
                bad "$name: expected=MISS but reference keys are IDENTICAL ($put_key) -- this fixture pair's 'flip' has no effect on the key formula as implemented; the fixture is vacuous"
            fi
        fi
    done

    # Named check for the excluded golden-bad scenario: the reference keys
    # of put/get MUST be IDENTICAL here (verdict plays no part in the key
    # formula) -- proving that IF a KILLED verdict had been stored under
    # this same key, get would find it, so the fixture's expected MISS
    # against the real tool (Section D) can only be explained by the
    # SURVIVED-never-reused rule, never by an accidental key mismatch.
    sv_put=$(python3 "$DEC23_PY" "$FIXDIR/mr_bad_survived_never_reused/put_envelope.json" 2>/dev/null)
    sv_get=$(python3 "$DEC23_PY" "$FIXDIR/mr_bad_survived_never_reused/get_envelope.json" 2>/dev/null)
    if [ -n "$sv_put" ] && [ "$sv_put" = "$sv_get" ]; then
        ok "mr_bad_survived_never_reused: reference keys of put/get envelopes are IDENTICAL ($sv_put) -- the expected MISS is provably the SURVIVED-never-reused rule, not a key mismatch"
    else
        bad "mr_bad_survived_never_reused: reference keys of put/get envelopes DIFFER (put=$sv_put get=$sv_get) -- this fixture accidentally also differs in a key-bearing field, contaminating the SURVIVED-rule check with a key-mismatch effect"
    fi

    # -------------------------------------------------------------------
    # mr_gate_isolation -- T057 case 1's "(not others)" half: every OTHER
    # scenario above uses one hardcoded gate id in its own isolated
    # scratch cache dir, so none of them alone proves that changing one
    # gate's input leaves an UNRELATED gate's cache entry, sharing the
    # SAME cache directory, untouched. Reference-check BEFORE Section D
    # claims anything about the real tool: gate A's put/get keys must
    # DIFFER (its own input changed), gate B's put/get keys must be
    # IDENTICAL (unchanged), and gate A's key must differ from gate B's
    # key (genuinely distinct gates, not an accidental collision that
    # would make "isolation" trivially true for the wrong reason).
    # -------------------------------------------------------------------
    GI_DIR="$FIXDIR/mr_gate_isolation"
    gi_a_put=$(python3 "$DEC23_PY" "$GI_DIR/gate_a_put.json" 2>/dev/null)
    gi_a_get=$(python3 "$DEC23_PY" "$GI_DIR/gate_a_get.json" 2>/dev/null)
    gi_b_put=$(python3 "$DEC23_PY" "$GI_DIR/gate_b_put.json" 2>/dev/null)
    gi_b_get=$(python3 "$DEC23_PY" "$GI_DIR/gate_b_get.json" 2>/dev/null)
    if [ -z "$gi_a_put" ] || [ -z "$gi_a_get" ] || [ -z "$gi_b_put" ] || [ -z "$gi_b_get" ]; then
        bad "mr_gate_isolation: reference key builder failed to compute a key from one of the 4 envelopes"
    else
        if [ "$gi_a_put" != "$gi_a_get" ]; then
            ok "mr_gate_isolation: gate A's reference keys DIFFER (put=$gi_a_put get=$gi_a_get) -- its changed input means its own mutation must re-run"
        else
            bad "mr_gate_isolation: gate A's reference keys are IDENTICAL ($gi_a_put) -- this fixture's 'gate A input changed' half is vacuous"
        fi
        if [ "$gi_b_put" = "$gi_b_get" ]; then
            ok "mr_gate_isolation: gate B's reference keys are IDENTICAL ($gi_b_put) -- its unchanged input means its cached verdict stays servable"
        else
            bad "mr_gate_isolation: gate B's reference keys DIFFER (put=$gi_b_put get=$gi_b_get) -- this fixture's 'gate B unchanged' half is vacuous"
        fi
        if [ "$gi_a_put" != "$gi_b_put" ]; then
            ok "mr_gate_isolation: gate A's key ($gi_a_put) differs from gate B's key ($gi_b_put) -- the two gates are genuinely distinct cache slots, not an accidental collision"
        else
            bad "mr_gate_isolation: gate A's key equals gate B's key ($gi_a_put) -- the two gates COLLIDE in the reference formula, which would make any 'isolation' observed against the real tool meaningless (both gates would share one cache slot for the wrong reason)"
        fi
    fi
fi

# =============================================================================
# Section C -- reference TCE normaliser + its own self-validation: proves
# the mr_tce_duplicate / mr_tce_distinct fixture pairs are non-vacuous
# BEFORE any claim is made about the absent real tool's `check-duplicate`.
# =============================================================================
if [ ! -f "$TCE_PY" ]; then
    bad "reference TCE normaliser missing at $TCE_PY -- Section C self-checks cannot run"
elif ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the reference TCE normaliser"
else
    DUP_A=$(python3 "$TCE_PY" "$FIXDIR/mr_tce_duplicate/mutant_a.sh" 2>/dev/null)
    DUP_B=$(python3 "$TCE_PY" "$FIXDIR/mr_tce_duplicate/mutant_b.sh" 2>/dev/null)
    if [ -n "$DUP_A" ] && [ "$DUP_A" = "$DUP_B" ]; then
        ok "mr_tce_duplicate: reference normalised digests of mutant_a.sh and mutant_b.sh are IDENTICAL ($DUP_A) -- differ only in comment/whitespace, matching expected=DUPLICATE"
    else
        bad "mr_tce_duplicate: expected normalised digests to match but got a=$DUP_A b=$DUP_B -- this fixture pair does not actually encode a comment/whitespace-only difference"
    fi

    DIS_A=$(python3 "$TCE_PY" "$FIXDIR/mr_tce_distinct/mutant_a.sh" 2>/dev/null)
    DIS_B=$(python3 "$TCE_PY" "$FIXDIR/mr_tce_distinct/mutant_b.sh" 2>/dev/null)
    if [ -n "$DIS_A" ] && [ -n "$DIS_B" ] && [ "$DIS_A" != "$DIS_B" ]; then
        ok "mr_tce_distinct: reference normalised digests of mutant_a.sh and mutant_b.sh DIFFER (a=$DIS_A b=$DIS_B) -- matching expected=DISTINCT, the negative control proving normalisation does not over-merge"
    else
        bad "mr_tce_distinct: expected normalised digests to differ but got a=$DIS_A b=$DIS_B -- this negative-control fixture is vacuous (the two mutants would be wrongly collapsed)"
    fi

    # Control needle on the normaliser itself: a '#' INSIDE a quoted string
    # (e.g. an echo of literal text containing '#') must be preserved, not
    # stripped as a comment -- proven with a small inline fixture, not
    # assumed, since a naive strip-at-first-'#' implementation would corrupt
    # any gate script that echoes text containing '#'.
    QUOTE_TMP=$(mktemp)
    printf '#!/bin/sh\necho "value#not-a-comment"  # real trailing comment\n' > "$QUOTE_TMP"
    QUOTE_DIGEST=$(python3 "$TCE_PY" "$QUOTE_TMP" 2>/dev/null)
    QUOTE_TMP2=$(mktemp)
    printf '#!/bin/sh\necho "value#not-a-comment"\n' > "$QUOTE_TMP2"
    QUOTE_DIGEST2=$(python3 "$TCE_PY" "$QUOTE_TMP2" 2>/dev/null)
    if [ -n "$QUOTE_DIGEST" ] && [ "$QUOTE_DIGEST" = "$QUOTE_DIGEST2" ]; then
        ok "control needle: a real trailing '#'-comment is stripped while a '#' INSIDE a double-quoted string is preserved -- the two otherwise-identical scripts (one with, one without, only the trailing comment) normalise to the SAME digest ($QUOTE_DIGEST)"
    else
        bad "control needle FAILED: quoted '#' handling is broken (with-comment=$QUOTE_DIGEST without-comment=$QUOTE_DIGEST2) -- the normaliser either strips a quoted '#' it should preserve, or fails to strip a real trailing comment"
    fi
    rm -f "$QUOTE_TMP" "$QUOTE_TMP2"
fi

# =============================================================================
# Section D -- the real functional checks: invoke $TOOL for every scenario.
# $TOOL is absent today, so every check below is the expected RED outcome,
# reported per-scenario (never collapsed into one opaque "tool missing"
# line), matching the established sibling convention (test_verdict_cache_red.sh).
# =============================================================================
CACHE_ROOT=$(mktemp -d) || { echo "FAIL: cannot create scratch cache-dir"; FAIL=$((FAIL+1)); CACHE_ROOT=""; }
trap '[ -n "${CACHE_ROOT:-}" ] && rm -rf "$CACHE_ROOT"' EXIT

run_put() {
    scen_dir=$1; cache_dir=$2; patch=$3; gate=$4
    verdict=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('verdict',''))" "$scen_dir/put_envelope.json" 2>/dev/null)
    python3 "$TOOL" put --cache-dir "$cache_dir" --gate GATE-MR-DEMO --mutation-id M-001 --patch "$patch" --gate-script "$gate" --inputs "$scen_dir/put_envelope.json" --verdict "$verdict" --evidence "$FIXDIR/evidence.txt"
}
run_get() {
    scen_dir=$1; cache_dir=$2; patch=$3; gate=$4
    python3 "$TOOL" get --cache-dir "$cache_dir" --gate GATE-MR-DEMO --mutation-id M-001 --patch "$patch" --gate-script "$gate" --inputs "$scen_dir/get_envelope.json"
}

for scen in mr_good_killed_reuse mr_bad_survived_never_reused mr_one_input_changed \
            mr_negctrl_mtime_only mr_flip_patch mr_flip_gate_script mr_flip_tool_version; do
    scen_dir="$FIXDIR/$scen"
    if [ ! -d "$scen_dir" ]; then
        bad "$scen: fixture directory missing at $scen_dir"
        continue
    fi
    want=$(head -n1 "$scen_dir/expected" 2>/dev/null | tr -d '\r\n')

    if [ ! -f "$TOOL" ]; then
        bad "RED: $scen (expected=$want) -- $TOOL is absent, cannot run get/put"
        continue
    fi
    if [ -z "${CACHE_ROOT:-}" ]; then
        bad "$scen: no scratch cache-dir available, skipping invocation"
        continue
    fi

    scen_cache="$CACHE_ROOT/$scen"
    mkdir -p "$scen_cache"
    case "$scen" in
        mr_flip_patch) get_patch="$FIXDIR/mutation_patch_v2.diff" ;;
        *) get_patch="$FIXDIR/mutation_patch.diff" ;;
    esac
    case "$scen" in
        mr_flip_gate_script) get_gate="$FIXDIR/gate_script_v2.sh" ;;
        *) get_gate="$FIXDIR/gate_script.sh" ;;
    esac

    run_put "$scen_dir" "$scen_cache" "$FIXDIR/mutation_patch.diff" "$FIXDIR/gate_script.sh" >"$scen_cache/.put_out" 2>"$scen_cache/.put_err"
    put_rc=$?
    run_get "$scen_dir" "$scen_cache" "$get_patch" "$get_gate" >"$scen_cache/.get_out" 2>"$scen_cache/.get_err"
    get_rc=$?
    get_out=$(cat "$scen_cache/.get_out")

    case "$want" in
        HIT)
            if [ "$get_rc" -eq 0 ] && printf '%s\n' "$get_out" | grep -q '^HIT '; then
                ok "$scen: get reports HIT as expected (rc=$get_rc)"
                if printf '%s\n' "$get_out" | grep -q 'verdict=SURVIVED'; then
                    bad "$scen: HIT output reports a SURVIVED verdict, which must never be servable (DEC-23)"
                fi
            else
                bad "$scen: expected HIT, got rc=$get_rc stdout='$get_out' (put rc=$put_rc)"
            fi
            ;;
        MISS)
            if [ "$get_rc" -eq 1 ] && printf '%s\n' "$get_out" | grep -q '^MISS '; then
                ok "$scen: get reports MISS as expected (rc=$get_rc)"
            else
                bad "$scen: expected MISS, got rc=$get_rc stdout='$get_out' (put rc=$put_rc)"
            fi
            ;;
        *)
            bad "$scen: fixture's expected file has no HIT/MISS first line"
            ;;
    esac
done

# =============================================================================
# Section D-bis -- mr_gate_isolation: T057 case 1's "(not others)" half.
# TWO independent gates (GATE-MR-ISO-A, GATE-MR-ISO-B) are put into ONE
# SHARED cache_dir (unlike every scenario above, each of which gets its
# own isolated scratch cache_dir per iteration of the main loop). Gate A's
# input then changes -> expect MISS. Gate B's input stays byte-identical
# in that SAME shared cache_dir -> expect HIT, proving gate A's change did
# not evict or otherwise disturb gate B's independently-cached entry.
# =============================================================================
GI_DIR="$FIXDIR/mr_gate_isolation"
if [ ! -d "$GI_DIR" ]; then
    bad "mr_gate_isolation: fixture directory missing at $GI_DIR"
elif [ ! -f "$TOOL" ]; then
    bad "RED: mr_gate_isolation gate A (expected=MISS) -- $TOOL is absent, cannot run get/put"
    bad "RED: mr_gate_isolation gate B (expected=HIT) -- $TOOL is absent, cannot run get/put"
elif [ -z "${CACHE_ROOT:-}" ]; then
    bad "mr_gate_isolation: no scratch cache-dir available, skipping invocation"
else
    gi_cache="$CACHE_ROOT/mr_gate_isolation"
    mkdir -p "$gi_cache"
    a_verdict=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('verdict',''))" "$GI_DIR/gate_a_put.json" 2>/dev/null)
    b_verdict=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('verdict',''))" "$GI_DIR/gate_b_put.json" 2>/dev/null)
    python3 "$TOOL" put --cache-dir "$gi_cache" --gate GATE-MR-ISO-A --mutation-id M-101 --patch "$FIXDIR/mutation_patch.diff" --gate-script "$FIXDIR/gate_script.sh" --inputs "$GI_DIR/gate_a_put.json" --verdict "$a_verdict" --evidence "$FIXDIR/evidence.txt" >"$gi_cache/.a_put_out" 2>"$gi_cache/.a_put_err"
    python3 "$TOOL" put --cache-dir "$gi_cache" --gate GATE-MR-ISO-B --mutation-id M-102 --patch "$FIXDIR/mutation_patch_v2.diff" --gate-script "$FIXDIR/gate_script_v2.sh" --inputs "$GI_DIR/gate_b_put.json" --verdict "$b_verdict" --evidence "$FIXDIR/evidence.txt" >"$gi_cache/.b_put_out" 2>"$gi_cache/.b_put_err"

    a_get_out=$(python3 "$TOOL" get --cache-dir "$gi_cache" --gate GATE-MR-ISO-A --mutation-id M-101 --patch "$FIXDIR/mutation_patch.diff" --gate-script "$FIXDIR/gate_script.sh" --inputs "$GI_DIR/gate_a_get.json" 2>"$gi_cache/.a_get_err")
    a_get_rc=$?
    b_get_out=$(python3 "$TOOL" get --cache-dir "$gi_cache" --gate GATE-MR-ISO-B --mutation-id M-102 --patch "$FIXDIR/mutation_patch_v2.diff" --gate-script "$FIXDIR/gate_script_v2.sh" --inputs "$GI_DIR/gate_b_get.json" 2>"$gi_cache/.b_get_err")
    b_get_rc=$?

    if [ "$a_get_rc" -eq 1 ] && printf '%s\n' "$a_get_out" | grep -q '^MISS '; then
        ok "mr_gate_isolation: gate A (changed input) reports MISS as expected (rc=$a_get_rc)"
    else
        bad "mr_gate_isolation: gate A expected MISS, got rc=$a_get_rc stdout='$a_get_out'"
    fi
    if [ "$b_get_rc" -eq 0 ] && printf '%s\n' "$b_get_out" | grep -q '^HIT '; then
        ok "mr_gate_isolation: gate B (unchanged input, SAME shared cache_dir as gate A) reports HIT as expected (rc=$b_get_rc) -- gate A's change did not touch it"
        if printf '%s\n' "$b_get_out" | grep -q 'verdict=SURVIVED'; then
            bad "mr_gate_isolation: gate B's HIT output reports a SURVIVED verdict, which must never be servable (DEC-23)"
        fi
    else
        bad "mr_gate_isolation: gate B expected HIT, got rc=$b_get_rc stdout='$b_get_out' -- either the tool never stored it, or gate A's put/get disturbed an unrelated gate's cache entry (the exact cross-gate leak T057 case 1 forbids)"
    fi
fi

for scen in mr_tce_duplicate mr_tce_distinct; do
    scen_dir="$FIXDIR/$scen"
    want=$(head -n1 "$scen_dir/expected" 2>/dev/null | tr -d '\r\n')
    if [ ! -f "$TOOL" ]; then
        bad "RED: $scen (expected=$want) -- $TOOL is absent, cannot run check-duplicate"
        continue
    fi
    out=$(python3 "$TOOL" check-duplicate --script-a "$scen_dir/mutant_a.sh" --script-b "$scen_dir/mutant_b.sh" 2>&1)
    rc=$?
    case "$want" in
        DUPLICATE)
            if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^DUPLICATE '; then
                ok "$scen: check-duplicate reports DUPLICATE as expected (rc=$rc)"
            else
                bad "$scen: expected DUPLICATE, got rc=$rc stdout='$out'"
            fi
            ;;
        DISTINCT)
            if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^DISTINCT'; then
                ok "$scen: check-duplicate reports DISTINCT as expected (rc=$rc)"
            else
                bad "$scen: expected DISTINCT, got rc=$rc stdout='$out'"
            fi
            ;;
    esac
done

echo
echo "=== T057 contract stub 1/3: put/get/check-duplicate wire format ==="
echo "===   (derived, binding-if-adopted on T-C07 per the header comment) ==="
echo "NOT YET IMPLEMENTED: mutation_reuse.py MUST accept 'put --cache-dir"
echo "  <dir> --gate <id> --mutation-id <id> --patch <diff> --gate-script"
echo "  <path> --inputs <envelope.json> --verdict KILLED|SURVIVED --evidence"
echo "  <path>' (exit 0, stdout 'PUT key=<hex64> verdict=<v>'; a SURVIVED"
echo "  verdict MAY be refused at put-time or silently not stored -- either"
echo "  is acceptable, but MUST NOT be servable by a later get) and 'get"
echo "  --cache-dir <dir> --gate <id> --mutation-id <id> --patch <diff>"
echo "  --gate-script <path> --inputs <envelope.json>' (exit 0 + 'HIT"
echo "  key=<hex64> verdict=KILLED' on a key match against a KILLED-only"
echo "  stored verdict; exit 1 + 'MISS key=<hex64>' otherwise, with NO"
echo "  verdict=SURVIVED token ever appearing in a HIT)."

echo
echo "=== T057 contract stub 2/3: DEC-23 key components + envelope shape ==="
echo "NOT YET IMPLEMENTED: the 4 DEC-23 key components (mutation patch"
echo "  bytes, target gate script bytes, gate's observed_inputs[].{path,"
echo "  sha256} sorted by path, tool_versions) are carried in ONE JSON"
echo "  document passed via --inputs, computed from patch/gate-script file"
echo "  bytes read separately (matching the CLI flags above) plus the"
echo "  envelope's own observed_inputs/tool_versions fields; recorded_mtime"
echo "  on each observed_inputs entry (if present) and verdict/mutation_id/"
echo "  gate_id (put-only bookkeeping) are explicitly OUTSIDE the key."

echo
echo "=== T057 contract stub 3/3: TCE dedup + honest scope ==="
echo "NOT YET IMPLEMENTED: 'check-duplicate --script-a <path> --script-b"
echo "  <path>' normalises both scripts per this file's comment/whitespace"
echo "  rule (see lib/tce_normalize_ref.py's header) and reports DUPLICATE"
echo "  (exit 0) or DISTINCT (exit 1). Mutation-cache PURGE/eviction and the"
echo "  flake-ledger interaction (T-C09) are NOT exercised by this RED"
echo "  test's fixtures -- see fixtures/mutation_reuse/README.md 'What this"
echo "  RED test does NOT cover'."

echo
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
