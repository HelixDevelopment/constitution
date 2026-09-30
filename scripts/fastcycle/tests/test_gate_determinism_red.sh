#!/bin/bash
# =============================================================================
# T155 RED test (SpecKit-004 "fast-dev-cycles", Phase 9 / User Story 7;
# plan.md T-G07; spec.md FR-021, SC-008).
# =============================================================================
#
# Task line (tasks.md T155, verbatim): "[P] [US7] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_gate_determinism_red.sh
# (golden-bad: a gate embedding a timestamp in its body FAILs the double
# run; golden: a canonical-body gate passes) (plan T-G07; FR-021, SC-008)".
#
# Plan.md T-G07 ("Determinism of the verifier and of every new gate"),
# verbatim Work line: "run the verifier and every new gate twice on the
# same state; compare SHA-256 of outputs; LLM-produced artefacts inside
# pipelines are replayed from their recorded outputs (DEC-16)." Its own
# "Protecting tests" line: "golden-bad: a gate that embeds a timestamp in
# its body output FAILs the double run; the fix removes it from the
# canonical body." FR-021: "Given the same repository state, the recursive
# verification and every gate MUST return byte-identical output on two
# consecutive runs."
#
# THE GAP (verified directly, 2026-09-30, control-needle-proven --
# 11.4.201(7)(b)/11.4.273, never assumed):
#
#   (a) The GENERIC single-command primitive this task needs is ALREADY
#       LANDED and already GREEN: `constitution/scripts/fastcycle/lib/
#       fc_common.py determinism-check -- CMD...` runs an arbitrary
#       command twice (the command writes its JSON doc to $FC_OUT), hashes
#       each run's canonical body (schema+body, excluding run_meta/
#       body_hash per contracts/common-conventions.md C-002) and exits 0
#       stable / 1 on a body_hash or rc mismatch (diff printed) / 3 self-
#       test failed / 4 no honest verdict -- confirmed present via `grep -n
#       determinism-check lib/fc_common.py` (cmd_determinism(), the
#       add_parser("determinism-check") wiring, and the dispatch table),
#       and already exhaustively regression-tested by the sibling
#       test_fc_common_red.sh (stable->0, differing body_hash->1, signal
#       death/missing command/non-JSON doc/hang/timeout all ->
#       4-never-1, multiple remediation rounds). This file therefore does
#       NOT reinvent that primitive (11.4.227 reuse-not-reinvention) --
#       Section B below invokes it directly, for real, as this file's OWN
#       non-vacuous reference computation.
#
#   (b) What genuinely does NOT exist anywhere in this checkout is the
#       SWEEP across "the verifier and every new gate" that plan T-G07's
#       Work line and tasks.md T160 (its implementation counterpart:
#       "Run repo_verify.py and every new gate from US1-US6 twice on the
#       same state; compare body_hash; ... results under
#       qa-results/fastcycle/us7/determinism/ until T155 is GREEN")
#       describe: no file anywhere under constitution/scripts/fastcycle/
#       matches `*determinism_sweep*` or `*gate_determinism*` (verified via
#       `grep -rln` over the whole fastcycle tree, zero hits besides this
#       file itself and existing per-command `determinism-check`/
#       `--determinism-check` support already present on repo_verify.py and
#       fc_common.py), and `qa-results/fastcycle/us7/determinism/` does not
#       exist on disk (only `qa-results/fastcycle/us7/red/` does) --
#       consistent with T160 never having run. THIS is the file's real
#       target: a sweep tool that, per gate, REUSES `fc_common.py
#       determinism-check` (never reimplements its process-management /
#       timeout / reaping logic) and aggregates a PASS/FAIL verdict per
#       gate into one report.
#
# CLI contract this file DEFINES for the not-yet-built sweep tool
# (UNCONFIRMED by any landed contract doc -- exact house precedent for this
# situation set by the sibling test_gate_order_red.sh's own EXEC_ORDER_KEY
# treatment of its equally-unconfirmed `execution_order` field: binding-if-
# adopted on the real T-G07/T160 implementation; if the real tool names its
# config/output fields differently, only the two constants below
# (SWEEP_TOOL, and the `verdict` vocabulary DETERMINISTIC/NONDETERMINISTIC)
# need updating, never this file's toy-gate fixture behaviour, which is
# governed only by the ALREADY-LANDED, ALREADY-STABLE fc_common.py
# contract exercised directly in Section B):
#
#   gate_determinism_sweep.py --config <gates.yaml> --out <report.json>
#
#   gates.yaml   : {schema: ..., gates: [{id: <str>, cmd: [<argv...>]}, ...]}
#   report.json  : {schema, results: [{gate_id, verdict, exit_code}],
#                    summary, run_meta} -- `verdict` drawn from
#                    {DETERMINISTIC, NONDETERMINISTIC, BLIND} per gate,
#                    mirroring fc_common.py determinism-check's own
#                    0/1/(3,4) exit-code taxonomy one-for-one.
#   Exit codes   : 0 every gate DETERMINISTIC; 1 any gate NONDETERMINISTIC;
#                    2 usage/config error; 4 any gate BLIND/self-test-failed
#                    (mirrors contracts/common-conventions.md C-001).
#
# Producer != Verifier (11.4.240): this file writes ONLY the RED test (plus
# its own toy-gate fixtures, generated at runtime into a mktemp scratch
# directory -- see the HARD SCOPE LIMIT note below). It does NOT implement
# verify/gate_determinism_sweep.py (a separate, later task), and never
# fabricates a tool-invocation result -- every PASS/FAIL claim below is
# either (a) a real, independent invocation of the ALREADY-LANDED
# fc_common.py primitive (Section B, expected to genuinely pass today), or
# (b) a real invocation of the (today, absent) sweep tool (Section C,
# expected to genuinely fail today because the file cannot be opened).
#
# HARD SCOPE LIMIT (imposed on this task, not a project-wide rule): this
# task may create/edit ONLY this one test file -- no new fixture files
# under tests/fixtures/. Both toy "gate" scripts this file needs are
# therefore written inline (heredocs) into a mktemp scratch directory at
# run time, never committed as separate fixtures, matching the established
# house pattern of building scratch configs/scripts inline (e.g.
# test_gate_audit_red.sh's own $WORK/scratch_fastcycle.yaml).
#
# Exit: 0 all as expected (unexpected today -- would mean T160's sweep tool
#       has already landed and both real invocations already match); 1 any
#       FAIL recorded (today: RED, expected for both Section C scenarios,
#       since verify/gate_determinism_sweep.py does not exist -- Section
#       B's reference checks are expected to PASS today, since they
#       exercise only the ALREADY-LANDED fc_common.py primitive, never the
#       absent sweep tool).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FCCOMMON="$FC/lib/fc_common.py"
SWEEP_TOOL="$FC/verify/gate_determinism_sweep.py"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok: $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok: $1"; }

echo "== T155 RED: determinism sweep across every gate (plan T-G07; FR-021, SC-008) =="

WORK=$(mktemp -d) || { echo "cannot create scratch dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# --- build the two toy "gate" fixtures this file needs, inline (see the
#     HARD SCOPE LIMIT note above) ---
mkdir -p "$WORK/gates"
cat > "$WORK/gates/gate_good_canonical.sh" <<'EOF'
#!/bin/sh
# Golden fixture: canonical, timestamp-free body -- every run byte-identical.
set -eu
cat > "$FC_OUT" <<JSON
{"schema": "toy-gate-good/v1", "check": "canonical-timestamp-free-body", "value": 42, "verdict": "PASS"}
JSON
exit 0
EOF
cat > "$WORK/gates/gate_bad_timestamp.sh" <<'EOF'
#!/bin/sh
# Golden-bad fixture: embeds a real nanosecond-precision wall-clock
# timestamp directly IN THE BODY (not under run_meta, which is the ONLY
# field the contract excludes from body_hash) -- every run differs.
set -eu
TS=$(date +%s%N)
cat > "$FC_OUT" <<JSON
{"schema": "toy-gate-bad/v1", "check": "embeds-a-real-timestamp-in-its-body", "generated_at": "$TS", "verdict": "PASS"}
JSON
exit 0
EOF
chmod +x "$WORK/gates/gate_good_canonical.sh" "$WORK/gates/gate_bad_timestamp.sh"

# =============================================================================
# Section A -- control needles (11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption carried over from tasks.md/plan.md.
# =============================================================================
echo "-- Section A: control needles --"

if [ -f "$FCCOMMON" ]; then
    ok "control needle #1: known-present sibling lib/fc_common.py resolves"
    echo "   through this file's own relative-path construction -- the"
    echo "   Section B reference computation below (which invokes it for"
    echo "   real) can be trusted"
else
    bad "control needle #1: lib/fc_common.py does not resolve at $FCCOMMON"
    echo "     -- this file's relative-path computation is broken; nothing"
    echo "     below can be trusted"
fi

if [ -x "$WORK/gates/gate_good_canonical.sh" ] && [ -x "$WORK/gates/gate_bad_timestamp.sh" ]; then
    ok "control needle #2: this file's own toy gate fixtures exist and are executable"
else
    bad "control needle #2: toy gate fixtures missing/non-executable -- fixture-authoring defect in THIS file"
fi

if [ -f "$SWEEP_TOOL" ]; then
    echo "ok tool exists at $SWEEP_TOOL -- the sweep half of T-G07/T160 has"
    echo "   landed; the real invocations in Section C below are the load-"
    echo "   bearing functional checks to run"
else
    echo "RED: $SWEEP_TOOL is absent -- the generic single-command"
    echo "     determinism primitive it is expected to REUSE"
    echo "     (lib/fc_common.py's ALREADY-LANDED 'determinism-check --"
    echo "     CMD...' subcommand, confirmed present and functioning for"
    echo "     real in Section B below) exists, but nothing sweeps it"
    echo "     across every gate yet -- confirming this file's own premise"
    echo "     is real, not assumed (11.4.6)."
fi

if [ ! -d "$ROOT/qa-results/fastcycle/us7/determinism" ]; then
    echo "   (context, not a pass/fail assertion: qa-results/fastcycle/us7/"
    echo "   determinism/ also does not exist on this checkout, consistent"
    echo "   with T160's sweep never having run)"
fi

# =============================================================================
# Section B -- reference self-check: this file's OWN direct invocation of
# the ALREADY-LANDED, already-tested (test_fc_common_red.sh) generic
# primitive `fc_common.py determinism-check -- CMD...`, never the (today,
# absent) sweep tool. Proves the two toy fixtures' design is genuinely
# non-vacuous BEFORE they are used to judge the absent sweep tool in
# Section C. This is real evidence, not a simulation: the PASS/FAIL below
# reflects fc_common.py's actual exit code against each toy gate, run for
# real, exactly matching the behaviour hand-verified while authoring this
# file (golden-bad -> "nondeterministic body_hash ... !=" on stderr, exit
# 1, with a unified diff showing the two runs' differing generated_at
# values; golden -> exit 0).
# =============================================================================
echo "-- Section B: reference determinism check via the existing lib/fc_common.py primitive --"

python3 "$FCCOMMON" determinism-check -- bash "$WORK/gates/gate_good_canonical.sh" \
    >"$WORK/ref_good.out" 2>"$WORK/ref_good.err"
REF_GOOD_RC=$?
if [ "$REF_GOOD_RC" -eq 0 ]; then
    ok "reference: gate_good_canonical.sh is genuinely DETERMINISTIC (fc_common.py determinism-check exit 0)"
else
    bad "reference: gate_good_canonical.sh unexpectedly rc=$REF_GOOD_RC (wanted 0) -- fixture-authoring defect: $(cat "$WORK/ref_good.err")"
fi

python3 "$FCCOMMON" determinism-check -- bash "$WORK/gates/gate_bad_timestamp.sh" \
    >"$WORK/ref_bad.out" 2>"$WORK/ref_bad.err"
REF_BAD_RC=$?
if [ "$REF_BAD_RC" -eq 1 ] && grep -q "nondeterministic" "$WORK/ref_bad.err"; then
    ok "reference: gate_bad_timestamp.sh is genuinely NONDETERMINISTIC (fc_common.py determinism-check exit 1, body_hash mismatch reported)"
else
    bad "reference: gate_bad_timestamp.sh unexpectedly rc=$REF_BAD_RC (wanted 1 with a nondeterministic body_hash message) -- fixture-authoring defect: $(cat "$WORK/ref_bad.err")"
fi

# =============================================================================
# Section C -- real invocations of the (today, absent) sweep tool. No
# special-casing on the tool's absence: `python3 "$SWEEP_TOOL" ...` is
# always genuinely invoked, exactly as it would be once T160 lands (house
# precedent: test_gate_audit_red.sh's self-flipping-polarity pattern --
# while the tool is absent, python3 refuses to open the nonexistent script
# (exit 2, no report written), which never matches either scenario's real
# expected outcome below, correctly driving that scenario to "NOT ok"
# today with NO further edits needed once the tool lands).
# =============================================================================
echo "-- Section C: real sweep-tool invocations (today: absent -> RED expected) --"

run_sweep() {
    # run_sweep <gate_id> <gate_script> <out.json>
    gid="$1"; script="$2"; out="$3"; cfg="$WORK/cfg_${gid}.yaml"
    cat > "$cfg" <<CFGEOF
schema: fastcycle-gate-determinism-sweep-config/v1
gates:
  - id: $gid
    cmd: ["bash", "$script"]
CFGEOF
    python3 "$SWEEP_TOOL" --config "$cfg" --out "$out"
}

extract_verdict() {
    # extract_verdict <report.json> <gate_id>
    python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print('<unreadable>'); sys.exit(0)
matches = [x for x in d.get('results', []) if x.get('gate_id') == sys.argv[2]]
print(matches[0].get('verdict', '<missing>') if matches else '<missing>')
" "$1" "$2" 2>/dev/null
}

echo "  scenario: golden-bad -- gate_bad_timestamp FAILs the double run"
OUT_BAD="$WORK/report_bad.json"
run_sweep "gate_bad_timestamp" "$WORK/gates/gate_bad_timestamp.sh" "$OUT_BAD" \
    >"$WORK/sweep_bad.out" 2>"$WORK/sweep_bad.err"
SWEEP_BAD_RC=$?
VERDICT_BAD=$(extract_verdict "$OUT_BAD" "gate_bad_timestamp")
if [ "$SWEEP_BAD_RC" -eq 1 ] && [ "$VERDICT_BAD" = "NONDETERMINISTIC" ]; then
    ok "golden-bad: sweep tool reports gate_bad_timestamp NONDETERMINISTIC, overall exit 1"
else
    bad "golden-bad: got exit=$SWEEP_BAD_RC verdict='$VERDICT_BAD' (wanted exit=1"
    echo "     verdict=NONDETERMINISTIC). Current reason: $SWEEP_TOOL does not"
    echo "     exist yet -- stderr: $(tail -1 "$WORK/sweep_bad.err" 2>/dev/null)"
fi

echo "  scenario: golden -- gate_good_canonical PASSes the double run"
OUT_GOOD="$WORK/report_good.json"
run_sweep "gate_good_canonical" "$WORK/gates/gate_good_canonical.sh" "$OUT_GOOD" \
    >"$WORK/sweep_good.out" 2>"$WORK/sweep_good.err"
SWEEP_GOOD_RC=$?
VERDICT_GOOD=$(extract_verdict "$OUT_GOOD" "gate_good_canonical")
if [ "$SWEEP_GOOD_RC" -eq 0 ] && [ "$VERDICT_GOOD" = "DETERMINISTIC" ]; then
    ok "golden: sweep tool reports gate_good_canonical DETERMINISTIC, overall exit 0"
else
    bad "golden: got exit=$SWEEP_GOOD_RC verdict='$VERDICT_GOOD' (wanted exit=0"
    echo "     verdict=DETERMINISTIC). Current reason: $SWEEP_TOOL does not"
    echo "     exist yet -- stderr: $(tail -1 "$WORK/sweep_good.err" 2>/dev/null)"
fi

echo "== T155 RED summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
