#!/bin/bash
# Purpose : T058 (SpecKit-004 "fast-dev-cycles", User Story 2) RED baseline
#           for `constitution/scripts/fastcycle/gates/gate_audit.py`
#           (plan.md T-C08 -- "Gate audit: vacuous, duplicate and
#           single-mention gates; propagation-family consolidation") --
#           proves the tool is absent today by GENUINELY INVOKING it (never
#           merely `[ -f ... ]`), and ships fixtures for the task line's 2
#           named behaviours (golden-bad: a removal without a transferred-
#           mutation record is refused; golden-output: the table-driven
#           propagation loop gives per-id verdicts identical to the
#           existing blocks) plus the taxonomy T-C08's own "Work:" line
#           requires classify() to compute (executing / named-only /
#           vacuous), under
#           constitution/scripts/fastcycle/tests/fixtures/gate_audit/.
#
# THE GAP (verified directly, 2026-09-28): plan.md places `gate_audit.py`
# under `constitution/scripts/fastcycle/gates/` -- that directory does not
# even exist yet (`ls constitution/scripts/fastcycle/gates/` -> No such
# file or directory). tasks.md's own T064 line names the implementer
# explicitly ("Implement ... gate_audit.py ... until T050/T058 is GREEN"),
# a LATER, SEPARATE task from this one.
#
# CLI-contract alignment (§11.4.251/§11.4.227 -- one tool, one interface,
# never two divergent specs for the same not-yet-built script): the SIBLING
# RED test test_catchset_compare_red.sh (T050, already landed) ALREADY
# exercises `gate_audit.py transfer-proof --config <yaml> --gate <id>
# --into <survivor-gate-id> --out <path>` for its own 2
# removal/transfer-proof fixtures. This file REUSES that EXACT sub-command
# shape for its own transfer-proof fixtures below rather than inventing a
# second, incompatible one. This file ADDS what T050 does not cover: (a)
# the FALSE-transfer-log-cited case (a log IS cited but proves the
# survivor does NOT fail on the removed gate's mutation -- distinct from
# T050's "no record at all" case), (b) the classify() taxonomy
# (executing/named-only/vacuous) via a NEW `classify --config <yaml>
# --gate <id>` sub-command this file introduces, and (c) the golden-output
# check against 5 REAL, frozen propagation-gate files from the live repo.
#
# Producer≠Verifier (§11.4.240): this file is authored at the RED step
# (T058); T064's implementation of gate_audit.py is a separate, later task
# this file's author never implements.
#
# RED, not a contract-stub bluff (§11.4.1/§11.4.6): this file does not
# merely PRINT prose describing the absent tool and exit 0 regardless.
# Section "REAL invocation assertions" below GENUINELY INVOKES
# `python3 $GATE_AUDIT ...` with realistic, contract-shaped arguments and
# asserts each run produces the REAL outcome named in that fixture's own
# expected.json (exact exit code / classification / verdict) -- never a
# blanket "must fail". While the tool is absent, python3 refuses to open
# the nonexistent script file (exit 2, no output), which never matches any
# fixture's real expected outcome, so every assertion correctly reports
# "NOT ok" today -- that is what drives this file's own exit code to
# nonzero. Once T064 lands, these same blocks keep testing something real
# with NO further edits needed: the assertion was always "does the real
# invocation match the fixture's real expected outcome", never "does the
# invocation merely fail" -- self-flipping polarity by construction.
#
# §11.4.273 control needles (three, independent):
#   #1 -- before trusting "gates/gate_audit.py is absent" as a finding, a
#         KNOWN-PRESENT sibling ($FC/lib/fc_common.sh) is confirmed to
#         resolve through this file's own relative-path construction first.
#   #2 -- ga_good_classify_vacuous is itself the classifier's negative-
#         class control needle: a classifier that labels EVERY invocable
#         gate "executing" (never detecting genuine vacuity) would still
#         pass ga_good_classify_executing alone -- this fixture is the one
#         case that proves the tool can see the negative class.
#   #3 -- before trusting the "no PATTERN found" PASS from
#         gate_survivor_narrow.sh as proof it does NOT absorb
#         BANNED_PATTERN_X, the KNOWN-CAUGHT case (gate_removed.sh against
#         the SAME target) is run first and confirmed to genuinely FAIL --
#         proving the target file + grep-based check combination CAN
#         signal a catch at all, before trusting the narrow survivor's
#         silence as a real miss rather than a broken fixture.
#
# §11.4.273 forensic instance (found + fixed during THIS file's own
# authoring, 2026-09-28, matching the class of bug T050/T051/T053/T054
# each independently caught): a first `for f in ...; do OUT="$(... | tail
# -3)"; echo "exit=$?" ...` loop used to hand-verify the golden-output
# real-sample fixture's expected PASS/FAIL verdicts reported "exit=0" for
# 3 of 5 files that were actually FAILing (exit=1) -- because `$?` after a
# pipeline captures the LAST command's (`tail`'s) exit status, not the
# gate script's, the exact §11.4.201(7)(c) pipeline-exit-status footgun
# this project's own constitution documents. Fixed by capturing `OUT="$(...
# 2>&1)"; RC=$?` in one statement with no trailing pipe, re-verified: real
# exit codes are 162=1, 167=1, 176=0, 187=1, 190=0 (recorded in
# ga_golden_output_real_ids/README.md). The fixed pattern is reused
# throughout this file's own real-invocation assertions below (RC="$?"
# captured immediately after each `python3 "$GATE_AUDIT" ...` call, no
# intervening pipe).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/gate_audit"
SHARED="$FIXDIR/_shared"
GATE_AUDIT="$FC/gates/gate_audit.py"

fail=0
failx() { fail=1; }

WORK=$(mktemp -d) || { echo "cannot create scratch dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# =============================================================================
# T085 Round 2 I-R2-7 remediation (2026-09-30): this file previously used
# "$ROOT/config/fastcycle/fastcycle.yaml" DIRECTLY -- the REAL, project-
# wide config -- so its transfer-proof() calls below wrote real toy
# records (TOY-GATE-REMOVED.json and others) into the REAL, production-
# consulted "qa-results/fastcycle/transfer_records/" directory. Reproduced
# live before this fix (§11.4.199): re-running this file left
# qa-results/fastcycle/transfer_records/TOY-GATE-REMOVED.json sitting in
# the real tree, silently pollutable into a real future catchset_compare.py
# `compare` decision -- the SAME class of bug the sibling
# test_catchset_compare_red.sh's own Round 1 I8(b) fix ALREADY closed for
# itself (that file's own header comment documents the identical repro).
# Fixed identically: a SCRATCH config under $WORK (cleaned by the SAME
# `trap ... EXIT` above) keeps every OTHER key ABSOLUTE and pointed at the
# SAME real sources, while redirecting ONLY transfer_records_dir into an
# isolated scratch subdirectory -- every path below is written ABSOLUTE
# (never relative), matching cfg_path()/cfg_path_list()'s os.path.join()
# absolute-overrides-root semantics this sibling fix's own comment already
# documents in full.
# =============================================================================
CFG="$WORK/scratch_fastcycle.yaml"
cat > "$CFG" <<EOF
schema: fastcycle-config/v1
paths:
  mutation_source: $ROOT/scripts/testing/meta_test_false_positive_proof.sh
  guard_registry: $ROOT/device/rockchip/rk3588/tests/regression_guard/registry.tsv
  workable_items_db: $ROOT/docs/workable_items.db
  gate_sites: $ROOT/config/fastcycle/gate_sites.yaml
  thresholds: $ROOT/config/fastcycle/thresholds.yaml
  consumers_seed: $ROOT/config/fastcycle/consumers.seed.tsv
  evidence_root: $ROOT/qa-results/fastcycle
  pre_build_verification: $ROOT/device/rockchip/rk3588/tests/pre_build_verification.sh
  gate_search_dirs:
    - $ROOT/constitution/scripts/fastcycle/tests/fixtures/catchset_compare/_shared/gates
  patch_search_dirs:
    - $ROOT/constitution/scripts/fastcycle/tests/fixtures/catchset_compare/_shared/patches
  base_tree_dirs:
    - $ROOT/constitution/scripts/fastcycle/tests/fixtures/catchset_compare/_shared/base_tree
  transfer_records_dir: $WORK/transfer_records
EOF

json_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }

# --- real-tree-untouched canary ---
CANARY="$FC/lib/fc_common.sh"
canary_hash() { sha256sum "$CANARY" 2>/dev/null | awk '{print $1}'; }
CANARY_BEFORE=$(canary_hash)

# --- §11.4.273 control needle #1: known-present sibling resolves ---
KNOWN_PRESENT="$FC/lib/fc_common.sh"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence check below proves"
  echo "     nothing (§11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.sh) resolves"
  echo "   through this test's own path construction -- the absence check"
  echo "   below can be trusted"
fi

# --- §11.4.273 control needle #3: the toy grep-based catch mechanism itself
#     genuinely CAN signal a catch, before trusting any PASS as a real miss ---
KNOWN_CATCH_OUT="$(bash "$SHARED/gates/gate_removed.sh" "$SHARED/targets/has_pattern_x.txt" 2>&1)"
KNOWN_CATCH_RC=$?
if [ "$KNOWN_CATCH_RC" -eq 1 ]; then
  echo "ok control needle #3: gate_removed.sh genuinely FAILs (exit 1) against"
  echo "   its own known-planted target -- the catch mechanism can signal a"
  echo "   catch at all, so gate_survivor_narrow.sh's later PASS on the same"
  echo "   target is trustworthy evidence of a real miss, not a broken fixture"
else
  echo "NOT ok control needle #3 failed: gate_removed.sh exit=$KNOWN_CATCH_RC"
  echo "     against a target it is SUPPOSED to catch -- $KNOWN_CATCH_OUT"
  failx
fi

# --- (1) absence proof: gate_audit.py ---
# Polarity (this IS the RED signal, deliberately -- the assertion below is
# "the guarded tool exists and is invocable", which is currently FALSE):
# absent -> "NOT ok" + failx (today's correct, expected RED state); present
# -> "ok" (T064 has landed; every real-invocation assertion further below
# then takes over as the load-bearing GREEN check against each fixture's
# REAL expected outcome).
if [ -f "$GATE_AUDIT" ]; then
  echo "ok $GATE_AUDIT now exists -- T064 has landed; the real-invocation"
  echo "   assertions below are the load-bearing check"
else
  echo "NOT ok $GATE_AUDIT does not exist yet (T064, a LATER task, has not"
  echo "     landed) -- this IS today's correct RED state"
  failx
fi

# --- (2) REAL invocation assertions: classification taxonomy ---
assert_classify_real() {
  local fx="$1" gate exp_class out rc actual
  gate=$(json_field "$FIXDIR/$fx/expected.json" gate_id)
  exp_class=$(json_field "$FIXDIR/$fx/expected.json" expected_classification)
  out="$(python3 "$GATE_AUDIT" classify --config "$CFG" \
    --registry "$SHARED/ledger/registry.tsv" \
    --deferrals "$SHARED/ledger/deferrals.tsv" \
    --gates-dir "$SHARED" --gate "$gate" \
    2>"$WORK/classify_${fx}.stderr")"
  rc=$?
  actual="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("classification",""))' 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$actual" = "$exp_class" ]; then
    echo "ok classify.$fx: real invocation classified $gate as '$actual' ="
    echo "   fixture's expected '$exp_class'"
  else
    echo "NOT ok classify.$fx: real invocation exit=$rc classification='$actual'"
    echo "     but fixture requires exit=0 classification='$exp_class'."
    echo "     Current reason: $GATE_AUDIT does not exist yet (T064 not landed)"
    echo "     -- stderr: $(tail -1 "$WORK/classify_${fx}.stderr" 2>/dev/null)"
    failx
  fi
}
assert_classify_real ga_good_classify_executing
assert_classify_real ga_good_classify_vacuous
assert_classify_real ga_good_classify_named_only

# --- (3) REAL invocation assertions: transfer-proof (T050's established
#     `transfer-proof --config --gate --into --out` contract, reused) ---
assert_transfer_proof_real() {
  local fx="$1" removed survivor out exp_verdict exp_reason_sub rc actual_verdict actual_reason
  out="$WORK/${fx}.transfer.json"
  rm -f "$out"
  removed=$(json_field "$FIXDIR/$fx/removal_request.json" removed_gate)
  survivor=$(json_field "$FIXDIR/$fx/removal_request.json" survivor_gate 2>/dev/null || echo "")
  if [ -n "$survivor" ]; then
    python3 "$GATE_AUDIT" transfer-proof --config "$CFG" \
      --gate "$removed" --into "$survivor" \
      --gates-dir "$SHARED" --out "$out" \
      >"$WORK/transfer_${fx}.stdout" 2>"$WORK/transfer_${fx}.stderr"
  else
    # ga_bad_no_transfer_record's own literal case: no survivor/transfer
    # field cited at all -- invoke with ONLY --gate, no --into/--out, per
    # the task text's "a removal without a transferred-mutation record".
    python3 "$GATE_AUDIT" transfer-proof --config "$CFG" \
      --gate "$removed" --gates-dir "$SHARED" \
      >"$WORK/transfer_${fx}.stdout" 2>"$WORK/transfer_${fx}.stderr"
  fi
  rc=$?
  exp_verdict=$(json_field "$FIXDIR/$fx/expected.json" verdict)
  exp_reason_sub=$(json_field "$FIXDIR/$fx/expected.json" reason 2>/dev/null || json_field "$FIXDIR/$fx/expected.json" reason_contains 2>/dev/null || echo "")
  if [ "$exp_verdict" = "ACCEPTED" ]; then
    actual_verdict=$([ "$rc" -eq 0 ] && echo "ACCEPTED" || echo "REFUSED")
  else
    actual_verdict=$([ "$rc" -ne 0 ] && echo "REFUSED" || echo "ACCEPTED")
  fi
  actual_reason="$(cat "$WORK/transfer_${fx}.stdout" "$WORK/transfer_${fx}.stderr" 2>/dev/null)"
  if [ "$actual_verdict" = "$exp_verdict" ] && printf '%s' "$actual_reason" | grep -qi -- "$exp_reason_sub"; then
    echo "ok transfer-proof.$fx: real invocation verdict=$actual_verdict matches"
    echo "   fixture's expected '$exp_verdict' with reason containing '$exp_reason_sub'"
  else
    echo "NOT ok transfer-proof.$fx: real invocation exit=$rc verdict=$actual_verdict"
    echo "     but fixture requires verdict='$exp_verdict' reason~'$exp_reason_sub'."
    echo "     Current reason: $GATE_AUDIT does not exist yet (T064 not landed)"
    echo "     -- stderr: $(tail -1 "$WORK/transfer_${fx}.stderr" 2>/dev/null)"
    failx
  fi
}
assert_transfer_proof_real ga_good_transfer_proof
assert_transfer_proof_real ga_bad_no_transfer_proof
assert_transfer_proof_real ga_bad_no_transfer_record

# --- (4) REAL invocation assertion: golden-output against 5 REAL frozen
#     propagation-gate files (see ga_golden_output_real_ids/README.md for
#     the hand-verified real exit codes + the pipeline-exit-status bug
#     this file's authoring caught and fixed before trusting them) ---
assert_golden_output_real() {
  local fx="ga_golden_output_real_ids" all_match=1 gid exp_class out rc actual
  for gid in CM-COVENANT-114-162-PROPAGATION CM-COVENANT-114-167-PROPAGATION \
             CM-COVENANT-114-176-PROPAGATION CM-COVENANT-114-187-PROPAGATION \
             CM-COVENANT-114-190-PROPAGATION; do
    exp_class="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["expected_classifications"][sys.argv[2]])' "$FIXDIR/$fx/expected.json" "$gid")"
    out="$(python3 "$GATE_AUDIT" classify --config "$CFG" \
      --gates-dir "$SHARED/real_sample" --gate "$gid" \
      2>"$WORK/golden_${gid}.stderr")"
    rc=$?
    actual="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("classification",""))' 2>/dev/null)"
    if [ "$rc" -ne 0 ] || [ "$actual" != "$exp_class" ]; then
      all_match=0
      echo "     $gid: real invocation exit=$rc classification='$actual', wants '$exp_class'"
    fi
  done
  if [ "$all_match" -eq 1 ]; then
    echo "ok golden-output.$fx: gate_audit.py classify matches all 5 real"
    echo "   frozen propagation-gate ids' hand-verified classification"
    echo "   (real family count used: 83 on-disk .sh files / 157-row data"
    echo "   pack, NOT the task text's stale '120' figure -- verified via"
    echo "   direct ls+wc against the live repo, §11.4.273)"
  else
    echo "NOT ok golden-output.$fx: one or more real-id classifications"
    echo "     did not match (see per-id lines above)."
    echo "     Current reason: $GATE_AUDIT does not exist yet (T064 not landed)"
    failx
  fi
}
assert_golden_output_real

# --- (5) REAL invocation assertion: negative control (no removal pending,
#     the whole toy corpus audited clean -- §11.4.201(1) false-positive
#     guard: a checker that refuses even a clean state is as broken as one
#     that accepts a bad removal) ---
assert_negctrl_real() {
  local fx="ga_negctrl_clean_state" exp_refused out rc actual_refused
  exp_refused=$(json_field "$FIXDIR/$fx/expected.json" expected_refused_count)
  out="$(python3 "$GATE_AUDIT" audit --config "$CFG" \
    --registry "$SHARED/ledger/registry.tsv" \
    --deferrals "$SHARED/ledger/deferrals.tsv" \
    --gates-dir "$SHARED" \
    2>"$WORK/negctrl.stderr")"
  rc=$?
  actual_refused="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("refused_count",-1))' 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$actual_refused" = "$exp_refused" ]; then
    echo "ok negctrl.$fx: real invocation reports refused_count=$actual_refused"
    echo "   matching the fixture's expected $exp_refused (the clean-state"
    echo "   false-positive guard holds)"
  else
    echo "NOT ok negctrl.$fx: real invocation exit=$rc refused_count='$actual_refused'"
    echo "     but fixture requires exit=0 refused_count=$exp_refused."
    echo "     Current reason: $GATE_AUDIT does not exist yet (T064 not landed)"
    echo "     -- stderr: $(tail -1 "$WORK/negctrl.stderr" 2>/dev/null)"
    failx
  fi
}
assert_negctrl_real

# --- (6) fixture presence: every scenario's required files ---
require_file() {
  if [ -f "$1" ]; then
    echo "ok fixture file present: ${1#"$FIXDIR"/}"
  else
    echo "NOT ok fixture file MISSING: ${1#"$FIXDIR"/}"
    failx
  fi
}
for g in gate_executing gate_vacuous gate_removed gate_survivor gate_survivor_narrow; do
  require_file "$SHARED/gates/$g.sh"
done
require_file "$SHARED/ledger/registry.tsv"
require_file "$SHARED/ledger/deferrals.tsv"
require_file "$SHARED/targets/clean.txt"
require_file "$SHARED/targets/has_pattern_x.txt"
require_file "$SHARED/transfer_runs/good_transfer_run.log"
require_file "$SHARED/transfer_runs/bad_transfer_run.log"
for f in 162 167 176 187 190; do
  require_file "$SHARED/real_sample/cm_covenant_114_${f}_propagation.sh"
done
require_file "$SHARED/real_sample/lib/covenant_propagation_engine.sh"
require_file "$SHARED/real_sample/lib/pointer_carrier.sh"
for fx in ga_good_classify_executing ga_good_classify_vacuous ga_good_classify_named_only \
          ga_good_transfer_proof ga_bad_no_transfer_proof ga_bad_no_transfer_record \
          ga_golden_output_real_ids ga_negctrl_clean_state; do
  require_file "$FIXDIR/$fx/expected.json"
  require_file "$FIXDIR/$fx/README.md"
done

# --- (7) real-tree-untouched canary re-check ---
CANARY_AFTER=$(canary_hash)
if [ "$CANARY_BEFORE" = "$CANARY_AFTER" ]; then
  echo "ok real-tree-untouched canary: $CANARY unchanged across this test run"
else
  echo "NOT ok real-tree-untouched canary: $CANARY changed during this run"
  echo "     ($CANARY_BEFORE -> $CANARY_AFTER) -- something outside the mktemp"
  echo "     scratch dir was mutated"
  failx
fi

echo "=================================================================="
if [ "$fail" -eq 0 ]; then
  echo "ALL OK (unexpected while T-C08's gate_audit.py is absent -- T064"
  echo "has landed and every real-invocation assertion above holds)"
  exit 0
else
  echo "RED (expected): gate_audit.py does not exist yet -- T064 is a"
  echo "later, separate task. Every real-invocation assertion above"
  echo "genuinely invoked the real (absent) tool and reported its own"
  echo "real per-fixture mismatch; none merely asserted absence."
  exit 1
fi
