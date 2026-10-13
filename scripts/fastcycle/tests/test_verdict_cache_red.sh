#!/bin/sh
# =============================================================================
# T051 RED test (SpecKit-004 "fast-dev-cycles", Phase 5 / User Story 2;
# plan.md T-C01; FR-007, FR-014, FR-021, SC-002).
# =============================================================================
#
# Purpose: prove, BEFORE the T068 implementation of
# `constitution/scripts/fastcycle/gates/verdict_cache.py` exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed — §11.4.6), and that its reuse target named in plan.md T-C01
#       ("ATM-659 WS10 POC reused") genuinely exists but is genuinely UNWIRED
#       (RC-43 in research.md: "no reuse construct in the script" — confirmed
#       live below, not copied from the research doc blind);
#   (B) this file's own reference implementation of the DEC-07 cache-key
#       formula is non-vacuous — flipping exactly one of the seven key
#       components really does change the reference digest, and leaving
#       every component byte-identical really does leave it unchanged —
#       proven by REAL sha256 computation (python3 hashlib), never merely
#       asserted (§11.4.273: a claim like "these two envelopes should
#       collide/differ" is not evidence until it is computed);
#   (C) once T068 lands, invoking the real tool through the SAME fixtures
#       produces the outcome (`HIT`/`MISS`) this file's reference key
#       formula independently predicts, for every one of the 9 scenarios
#       under fixtures/verdict_cache/ (see that directory's own README.md
#       for the full scenario table and the contract citations backing
#       each one).
#
# Contract: specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
#   VC-001 (key formula, DEC-07 field order) .. VC-005 (backstop, out of
#   scope here — see fixtures/verdict_cache/README.md "What this RED test
#   does NOT cover"). data-model.md §5 "Verdict Cache Entry" is the
#   authoritative field list this file's reference key builder implements.
#
# Task line (tasks.md T051, verbatim): "RED test
# constitution/scripts/fastcycle/tests/test_verdict_cache_red.sh with
# fixtures constitution/scripts/fastcycle/tests/fixtures/verdict_cache/ per
# contract affected-set-and-verdict-cache (FR-007: flip one byte of one
# observed input -> the check re-runs and the stale verdict is not
# reported; golden: unchanged inputs -> hit; golden-bad: a key omitting one
# traced input is refused by the key-completeness check; negative control:
# mtime-only change -> hit; planted tool-version change -> miss)".
#
# --inputs <trace.json> envelope schema: UNCONFIRMED by the contract itself
# (it names 5 CLI flags but DEC-07's key has 7 components) — DEFINED here,
# binding-if-adopted on T068, exactly per the established house precedent
# (fixtures/dispatch_stamp/'s own README.md, test_build_deploy_qa_events_red.sh's
# "Contract for T040 implementer (UNCONFIRMED...)" section). Full schema +
# rationale: fixtures/verdict_cache/README.md.
#
# get/put stdout+exit-code wire format: ALSO UNCONFIRMED by the contract
# (which states semantics — VC-001..VC-005 — but not literal stdout
# strings); DEFINED here for this file's own GREEN-branch (used once T068
# lands), binding-if-adopted:
#   put <cache-dir> <gate> <inputs> <verdict> <evidence>:
#     verdict in {PASS,FAIL}: exit 0, stdout line "PUT key=<hex64> verdict=<v>"
#     verdict NOT in {PASS,FAIL} (VC-003 admission): tool MAY refuse (any
#       nonzero exit) OR MAY silently accept without storing — EITHER is
#       accepted by this file; the load-bearing assertion is the SUBSEQUENT
#       get() reporting MISS regardless (vc_admission_skip_never_cached/).
#   get <cache-dir> <gate> <inputs>:
#     HIT:  exit 0, stdout's FIRST line is "HIT key=<hex64> verdict=<v> evidence=<path>"
#     MISS: exit 1, stdout's FIRST line is "MISS key=<hex64>" (or a
#           key=UNKNOWN token when the key cannot be computed at all); a
#           MISS's stdout MUST NOT contain the string "verdict=PASS" nor
#           "verdict=FAIL" anywhere (this is the literal FR-007 check: "the
#           stale verdict is not reported").
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test + the
# fixtures under fixtures/verdict_cache/ (created earlier in this same task).
# It does NOT implement gates/verdict_cache.py (T068, a separate later
# task), and never fabricates a tool invocation result — every HIT/MISS
# claim below is either (a) a real reference-key computation this file
# performs itself with python3 hashlib, or (b) a real invocation of the
# (today, absent) tool, reported RED because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected FAIL>0
#       for every scenario's "tool invocation" check — the reference-key
#       self-checks in Section B are expected to PASS today, since they
#       exercise only this file's own computation, not the absent tool).

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/verdict_cache.py"
WS10_POC="$FC/../../../docs/research/tokens/ws10_testing_strategy/POC/verdict_cache_poc.py"
FIXDIR="$HERE/fixtures/verdict_cache"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T051 RED: content-addressed verdict cache (plan T-C01; FR-007, FR-014, FR-021, SC-002) =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from research.md/plan.md.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T068 has landed; the invocation checks"
    echo "   in Section C below are the real functional tests to run"
else
    echo "RED: $TOOL is absent -- T068 (gates/verdict_cache.py) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

if [ -f "$WS10_POC" ]; then
    ok "control needle: the WS10 POC plan.md T-C01 cites as its reuse"
    echo "   target (ATM-659 verdict_cache_poc.py) genuinely exists at"
    echo "   $WS10_POC"
else
    bad "control needle FAILED: the WS10 POC does not exist at $WS10_POC --"
    echo "   plan.md T-C01's Origin line ('ATM-659 WS10 POC reused') cannot"
    echo "   be verified against a real file"
fi
if [ -d "$FC/gates" ]; then
    if [ -n "$(find "$FC/gates" -maxdepth 1 -name '*.py' -exec grep -l 'verdict_cache_poc\|import verdict_cache_poc' {} \; 2>/dev/null)" ]; then
        bad "control needle FAILED: something under $FC/gates already imports"
        echo "   verdict_cache_poc -- research.md RC-43 ('no reuse construct in"
        echo "   the script') would then be stale; re-check before trusting"
        echo "   the rest of this file"
    else
        ok "control needle: RC-43 ('no verdict cache: identical checks re-run"
        echo "   on unchanged inputs ... no reuse construct') confirmed LIVE --"
        echo "   nothing under $FC/gates/ imports or invokes the WS10 POC today"
    fi
else
    echo "SKIP: $FC/gates/ does not exist yet -- Setup phase (T001-T006) has"
    echo "      not created it; the RC-43 needle above is therefore vacuously"
    echo "      true (nothing can import anything from a directory that does"
    echo "      not exist) and is NOT counted as a separate pass"
fi

# =============================================================================
# Section B -- reference DEC-07 key builder + its own self-validation
# (§11.4.107(10)/§11.4.273): this is THIS FILE's independent, from-scratch
# implementation of the VC-001 formula, used ONLY to prove the fixture pairs
# under fixtures/verdict_cache/ are non-vacuous BEFORE any claim is made
# about what the (absent) real tool should do with them. It never claims to
# BE verdict_cache.py, and it never seeds or informs T068's own
# implementation (this ordering — reference computation authored before the
# implementer's own code exists — is what makes the self-check meaningful:
# an implementation cannot have been reverse-engineered from it).
# =============================================================================
DEC07_PY="$HERE/lib/dec07_key_ref.py"

if [ ! -f "$DEC07_PY" ]; then
    bad "reference DEC-07 key builder missing at $DEC07_PY -- Section B self-checks cannot run"
elif ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the reference DEC-07 key builder"
else
    K1=$(python3 "$DEC07_PY" "$FIXDIR/unchanged_hit/put_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
    if [ -z "$K1" ]; then
        bad "reference key builder produced no output on unchanged_hit/put_envelope.json"
    else
        ok "reference DEC-07 key builder runs and produces a key ($K1)"
    fi

    # Self-validation of the reference builder itself, BEFORE trusting it to
    # judge any fixture (§11.4.107(10)): two structurally-identical
    # envelopes differing only in JSON key/list ORDER (Python dicts preserve
    # insertion order and JSON arrays are ordered; the `sorted()` calls
    # inside dec07_key_ref.py must neutralise that for observed_inputs, and
    # dict iteration order must never leak into tool_versions/env_allowlist)
    # must yield the SAME key. Proven, not assumed: unchanged_hit's own
    # put_envelope.json is copied and every JSON object's key order plus the
    # observed_inputs array order are reversed with python3 -- a builder
    # that (bug) hashed raw insertion/array order instead of a canonical
    # sorted form would produce a DIFFERENT key here and this needle would
    # catch it before any fixture verdict is trusted.
    REORDER_JSON=$(mktemp)
    python3 - "$FIXDIR/unchanged_hit/put_envelope.json" "$REORDER_JSON" <<'PYEOF'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    env = json.load(f)
reordered = {
    "observed_inputs": list(reversed(env["observed_inputs"])),
    "env_allowlist": dict(reversed(list(env["env_allowlist"].items()))),
    "tool_versions": dict(reversed(list(env["tool_versions"].items()))),
    "verdict": env["verdict"],
    "evidence": env["evidence"],
    "mutation_id": env["mutation_id"],
    "target_fingerprint": env["target_fingerprint"],
    "gate_script": env["gate_script"],
    "gate_id": env["gate_id"],
}
with open(dst, "w") as f:
    json.dump(reordered, f)
PYEOF
    K1_REORDERED=$(python3 "$DEC07_PY" "$REORDER_JSON" "$FIXDIR/gate_script.sh" 2>/dev/null)
    if [ -n "$K1" ] && [ "$K1" = "$K1_REORDERED" ]; then
        ok "control needle: reordering every JSON object's keys and the observed_inputs array does not change the reference key ($K1) -- the builder canonicalises order, it does not accidentally hash it"
    else
        bad "control needle FAILED: reordering JSON key/array order changed the reference key (original=$K1 reordered=$K1_REORDERED) -- dec07_key_ref.py leaks non-semantic JSON ordering into the key, making every HIT/MISS claim below unreliable"
    fi
    rm -f "$REORDER_JSON"

    # -------------------------------------------------------------------
    # Per-scenario reference computation: for every directory under
    # fixtures/verdict_cache/ that has put_envelope.json + get_envelope.json
    # + expected, compute the reference key of BOTH envelopes and check
    # (put_key == get_key) iff expected says HIT.
    # -------------------------------------------------------------------
    # vc_admission_skip_never_cached is deliberately EXCLUDED from this
    # generic key-diff loop: its put/get envelopes differ ONLY in
    # `verdict` (SKIP vs the field being entirely absent from get, since
    # get never carries a verdict at all) -- and `verdict` is, correctly,
    # NOT one of the 7 DEC-07 key components (VC-001: verdict is the
    # STORED value, never an input to its own lookup key). Its expected
    # MISS therefore comes from VC-003's ADMISSION rule ("only PASS/FAIL
    # ... are cached"), not from a key mismatch -- treating it as a
    # key-diff case here would either wrongly fail (the keys legitimately
    # collide) or, worse, silently mask a REAL admission-refusal bug by
    # confusing it with the wrong mechanism. It is asserted separately,
    # by name, immediately after this loop (§11.4.273: caught by running
    # the computation, not by assuming every "MISS" fixture has the same
    # shape).
    for scen in "$FIXDIR"/*/; do
        name=$(basename "$scen")
        [ "$name" = vc_admission_skip_never_cached ] && continue
        [ -f "$scen/put_envelope.json" ] || continue
        [ -f "$scen/get_envelope.json" ] || continue
        [ -f "$scen/expected" ] || continue
        want=$(head -n1 "$scen/expected" | tr -d '\r\n')
        case "$want" in
            HIT|MISS) : ;;
            *) bad "$name: expected file's first line is '$want', not HIT/MISS"; continue ;;
        esac
        put_key=$(python3 "$DEC07_PY" "$scen/put_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
        get_key=$(python3 "$DEC07_PY" "$scen/get_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
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

    # Named check for the excluded admission scenario: the reference keys
    # of put/get MUST be IDENTICAL here (verdict plays no part in the key
    # formula) -- proving that IF a PASS/FAIL had been stored under this
    # same key, get would have found it, so the fixture's expected MISS
    # against the real tool (Section C) can only be explained by VC-003
    # admission refusal, never by an accidental key mismatch that a
    # weaker test could not tell apart from the real defect class.
    adm_put=$(python3 "$DEC07_PY" "$FIXDIR/vc_admission_skip_never_cached/put_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
    adm_get=$(python3 "$DEC07_PY" "$FIXDIR/vc_admission_skip_never_cached/get_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
    if [ -n "$adm_put" ] && [ "$adm_put" = "$adm_get" ]; then
        ok "vc_admission_skip_never_cached: reference keys of put/get envelopes are IDENTICAL ($adm_put) -- the expected MISS is provably an admission-policy refusal (VC-003), not a key mismatch"
    else
        bad "vc_admission_skip_never_cached: reference keys of put/get envelopes DIFFER (put=$adm_put get=$adm_get) -- this fixture accidentally also differs in a key-bearing field, contaminating the admission-rule check with a key-mismatch effect"
    fi

    # Negative control on the reference builder itself: two envelopes that
    # differ ONLY in a field the formula must exclude (recorded_mtime) must
    # still key identically -- already covered by the vc_negctrl_mtime_only
    # loop iteration above, but restated here as an explicit, named
    # assertion so it cannot be missed inside the generic loop's output.
    mt_put=$(python3 "$DEC07_PY" "$FIXDIR/vc_negctrl_mtime_only/put_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
    mt_get=$(python3 "$DEC07_PY" "$FIXDIR/vc_negctrl_mtime_only/get_envelope.json" "$FIXDIR/gate_script.sh" 2>/dev/null)
    if [ -n "$mt_put" ] && [ "$mt_put" = "$mt_get" ]; then
        ok "named check: mtime-only difference does not change the reference key (content, not mtime, decides -- VC-002)"
    else
        bad "named check: mtime-only difference changed the reference key (put=$mt_put get=$mt_get) -- VC-002 would be violated by this formula"
    fi
fi

# =============================================================================
# Section C -- the real functional checks: invoke $TOOL (via `put` then
# `get`) for every scenario. $TOOL is absent today, so every check below is
# the expected RED outcome, reported per-scenario (never collapsed into one
# opaque "tool missing" line) so each is individually visible, matching the
# established sibling convention (test_dispatch_stamp_red.sh,
# test_build_deploy_qa_events_red.sh).
# =============================================================================
CACHE_ROOT=$(mktemp -d) || { echo "FAIL: cannot create scratch cache-dir"; FAIL=$((FAIL+1)); CACHE_ROOT=""; }
trap '[ -n "${CACHE_ROOT:-}" ] && rm -rf "$CACHE_ROOT"' EXIT

run_put() {
    scen_dir=$1; cache_dir=$2
    verdict=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('verdict',''))" "$scen_dir/put_envelope.json" 2>/dev/null)
    if [ -x "$TOOL" ]; then
        "$TOOL" put --cache-dir "$cache_dir" --gate GATE-VC-DEMO --inputs "$scen_dir/put_envelope.json" --verdict "$verdict" --evidence "$FIXDIR/evidence.txt"
    else
        python3 "$TOOL" put --cache-dir "$cache_dir" --gate GATE-VC-DEMO --inputs "$scen_dir/put_envelope.json" --verdict "$verdict" --evidence "$FIXDIR/evidence.txt"
    fi
}
run_get() {
    scen_dir=$1; cache_dir=$2
    if [ -x "$TOOL" ]; then
        "$TOOL" get --cache-dir "$cache_dir" --gate GATE-VC-DEMO --inputs "$scen_dir/get_envelope.json"
    else
        python3 "$TOOL" get --cache-dir "$cache_dir" --gate GATE-VC-DEMO --inputs "$scen_dir/get_envelope.json"
    fi
}

for scen in unchanged_hit vc_one_byte_flip vc_key_completeness_drop vc_negctrl_mtime_only \
            vc_flip_tool_version vc_flip_env vc_flip_mutation_id \
            vc_negctrl_irrelevant_file vc_admission_skip_never_cached; do
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

    run_put "$scen_dir" "$scen_cache" >"$scen_cache/.put_out" 2>"$scen_cache/.put_err"
    put_rc=$?
    run_get "$scen_dir" "$scen_cache" >"$scen_cache/.get_out" 2>"$scen_cache/.get_err"
    get_rc=$?
    get_out=$(cat "$scen_cache/.get_out")

    case "$want" in
        HIT)
            if [ "$get_rc" -eq 0 ] && printf '%s\n' "$get_out" | grep -q '^HIT '; then
                ok "$scen: get reports HIT as expected (rc=$get_rc)"
            else
                bad "$scen: expected HIT, got rc=$get_rc stdout='$get_out' (put rc=$put_rc)"
            fi
            ;;
        MISS)
            if [ "$get_rc" -eq 1 ] && printf '%s\n' "$get_out" | grep -q '^MISS '; then
                ok "$scen: get reports MISS as expected (rc=$get_rc)"
                if grep -q 'STALE_PASS_ABSENT' "$scen_dir/expected" 2>/dev/null; then
                    if printf '%s\n' "$get_out" | grep -q 'verdict=PASS\|verdict=FAIL'; then
                        bad "$scen: MISS output still contains a stale verdict= token (FR-007 violated): '$get_out'"
                    else
                        ok "$scen: MISS output contains no stale verdict= token (FR-007 satisfied)"
                    fi
                fi
            else
                bad "$scen: expected MISS, got rc=$get_rc stdout='$get_out' (put rc=$put_rc)"
            fi
            ;;
        *)
            bad "$scen: fixture's expected file has no HIT/MISS first line"
            ;;
    esac
done

echo
echo "=== T051 contract stub 1/3: get/put/purge wire format (derived, ==="
echo "===   binding on T068 per the header comment above) ==="
echo "NOT YET IMPLEMENTED: verdict_cache.py MUST accept 'put --cache-dir <dir>"
echo "  --gate <gate_id> --inputs <trace.json> --verdict PASS|FAIL --evidence"
echo "  <path>' (exit 0, stdout 'PUT key=<hex64> verdict=<v>' on a cacheable"
echo "  verdict; a non-PASS/FAIL verdict per VC-003 MAY be refused at put-time"
echo "  or silently not stored -- either is acceptable, but MUST NOT be"
echo "  servable by a later get) and 'get --cache-dir <dir> --gate <gate_id>"
echo "  --inputs <trace.json>' (exit 0 + 'HIT key=<hex64> verdict=<v>"
echo "  evidence=<path>' on a key match recomputed from the CURRENT bytes of"
echo "  every trace.json component per VC-001/VC-002; exit 1 + 'MISS"
echo "  key=<hex64>' with NO verdict= token anywhere in stdout otherwise)."

echo
echo "=== T051 contract stub 2/3: --inputs envelope (see fixtures/ ==="
echo "===   verdict_cache/README.md for the full schema + rationale) ==="
echo "NOT YET IMPLEMENTED: the 7 DEC-07 key components (gate-script bytes,"
echo "  gate id, observed_inputs[].{path,sha256} sorted by path,"
echo "  tool_versions, env_allowlist, target_fingerprint, mutation_id) are"
echo "  carried in ONE JSON document passed via --inputs; recorded_mtime on"
echo "  each observed_inputs entry (if present) and verdict/evidence (put"
echo "  only) are explicitly OUTSIDE the key per VC-002/data-model.md §5."

echo
echo "=== T051 contract stub 3/3: admission + honest scope (VC-003) ==="
echo "NOT YET IMPLEMENTED: only PASS/FAIL verdicts from a COMPLETE run are"
echo "  ever servable by get -- vc_admission_skip_never_cached/ proves a SKIP"
echo "  verdict must MISS on the very next get even with byte-identical"
echo "  inputs. VC-003's '>=2 consecutive identical verdicts before"
echo "  admission' rule and VC-004's flaky-purge rule are NOT exercised by"
echo "  this RED test's fixtures (see fixtures/verdict_cache/README.md"
echo "  'What this RED test does NOT cover') -- T068's own implementation"
echo "  tests must cover them; test_flake_ledger_red.sh (T059) contract-binds"
echo "  the 'never cached while FLAKY' half."

echo
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
