#!/bin/bash
# test_review_record_gate_authority_r1_regression.sh
#
# T048 restart, independent review round 1, report R7
# (docs/qa/t048_restart_round1_20261008/R7_review_record_metatest.md):
# regression suite for the defect CLASS "the gate trusts unauthenticated
# record fields" (R7 B1/B2/I1/I2/I3/M-a) in review/review_record.py.
#
# Class members (R7 + this fix's own enumeration, see the module docstring of
# review_record.py "Verdict authority"): verdict, findings, round, model_tier,
# effort, reviewer identity, producer identity, same-round precedence,
# evidence-path base, precheck all_pass/schema/batch binding, dispatch reuse,
# round budget, per-slice verdicts, record body integrity, backfill rows,
# seam/independence tier.
#
# Every case drives the REAL `review_record.py record` / `gate` CLI (or, for
# the single capability-tier case, the real module's own main() in-process
# with only os.geteuid substituted -- the one host condition a single-uid
# test host cannot otherwise produce). Nothing here re-implements gate logic
# (constitution 11.4.276(D)). Each reviewer mutation M1..M4 from R7 B2 has a
# dedicated scenario below in which EVERY other qualification condition
# holds, so removing the one guarded condition flips the verdict; the paired
# mutation runner is test_review_record_gate_authority_mutations.sh.
#
# Usage : bash test_review_record_gate_authority_r1_regression.sh
# Exit  : 0 all checks pass; 1 any check failed; 2 scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$FC/review/review_record.py"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own; the precheck pack runs shellcheck without -x
. "$HERE/lib/review_record_genuine.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'chmod -R u+w "$S" 2>/dev/null; rm -rf "$S"' EXIT INT TERM
RR_WORK="$S/work"; mkdir -p "$RR_WORK"
NONE='[]'

# fresh_case NAME: a new isolated records dir + ledger for one scenario.
fresh_case() {
  CASE="$S/$1"; mkdir -p "$CASE/records"
  RR_LEDGER="$CASE/ledger.jsonl"; : > "$RR_LEDGER"
  REC="$CASE/records"
}
gate() { # gate CHANGE [extra args] -> sets G_RC, G_OUT
  G_OUT=$(python3 "$RR_TOOL" gate --change "$1" --records "$REC" --dispatch-ledger "$RR_LEDGER" "${@:2}" 2>&1)
  G_RC=$?
}
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d.get(sys.argv[2])))' "$1" "$2" 2>/dev/null; }
covered()   { [ "$G_RC" -eq 0 ] && printf '%s\n' "$G_OUT" | grep -q "^COVERED $1 "; }
uncovered() { [ "$G_RC" -eq 1 ] && printf '%s\n' "$G_OUT" | grep -q "^UNCOVERED $1"; }

echo "== R7 B1/B2/I1-I3 regression: review_record.py gate verdict authority =="

# --- G0 negative control: a genuine reviewer-authored GO is COVERED --------
fresh_case g0
rr_genuine "$REC/r1.json" B-G0 CH-G0 1 GO "$NONE" D-G0
gate CH-G0
if [ "$RR_RC" -eq 0 ] && covered CH-G0 && printf '%s\n' "$G_OUT" | grep -q "independence=instance"; then
  ok "G0 negative control: genuine record COVERED at ordinary seam, achieved independence honestly reported 'instance' on this single-uid host"
else bad "G0: rc_record=$RR_RC rc_gate=$G_RC out=$G_OUT err=$(cat "$RR_WORK/r1/record.err")"; fi
TIER=$(field "$REC/r1.json" independence_tier)
if [ "$TIER" = '"instance"' ]; then ok "G0b: record stores the ACHIEVED tier 'instance' (never 'capability' on a same-uid write)"
else bad "G0b: independence_tier=$TIER"; fi

# --- B1 probe A: producer-authored verdict (no reviewer identity) ----------
fresh_case b1a
RR_NO_REVIEWER=1 rr_genuine "$REC/r1.json" B-B1A CH-B1A 1 GO "$NONE" D-B1A
gate CH-B1A
if uncovered CH-B1A; then ok "B1-A: a verdict carrying no reviewer identity never qualifies (producer self-certification)"
else bad "B1-A: rc=$G_RC out=$G_OUT"; fi

# --- B1 probe A2: precheck all_pass=false ----------------------------------
fresh_case b1a2
RR_PRECHECK_ALL_PASS=false rr_genuine "$REC/r1.json" B-B1A2 CH-B1A2 1 GO "$NONE" D-B1A2
gate CH-B1A2
if uncovered CH-B1A2 && printf '%s\n' "$G_OUT" | grep -q "all_pass"; then ok "B1-A2: archived precheck with all_pass=false never qualifies (named in reason)"
else bad "B1-A2: rc=$G_RC out=$G_OUT"; fi

# --- B1 probe A3: precheck schema not precheck/v1 --------------------------
fresh_case b1a3
RR_PRECHECK_SCHEMA='<none>' rr_genuine "$REC/r1.json" B-B1A3 CH-B1A3 1 GO "$NONE" D-B1A3
gate CH-B1A3
if uncovered CH-B1A3 && printf '%s\n' "$G_OUT" | grep -q "schema"; then ok "B1-A3: archived precheck without schema precheck/v1 never qualifies"
else bad "B1-A3: rc=$G_RC out=$G_OUT"; fi

# --- B1 probe A4: reviewer dispatch absent from ledger / no ledger ---------
fresh_case b1a4
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-B1A4 CH-B1A4 1 GO "$NONE" D-FORGED
gate CH-B1A4
if uncovered CH-B1A4 && printf '%s\n' "$G_OUT" | grep -q "dispatch"; then ok "B1-A4: a reviewer dispatch id with no dispatch-ledger row never qualifies"
else bad "B1-A4: rc=$G_RC out=$G_OUT"; fi
rr_ledger_row D-FORGED opus xhigh
G_OUT=$(python3 "$RR_TOOL" gate --change CH-B1A4 --records "$REC" 2>&1); G_RC=$?
if uncovered CH-B1A4; then ok "B1-A4b: gate run with NO --dispatch-ledger cannot authenticate any reviewer -> UNCOVERED, never a silent pass"
else bad "B1-A4b: rc=$G_RC out=$G_OUT"; fi

# --- B1 probe A5: ledger label disagrees with the claimed tier/effort -----
fresh_case b1a5
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-B1A5 CH-B1A5 1 GO "$NONE" D-B1A5
rr_ledger_row D-B1A5 opus high
gate CH-B1A5
if uncovered CH-B1A5; then ok "B1-A5: ledger label 'opus - high' contradicts the verdict's claimed xhigh -> UNCOVERED"
else bad "B1-A5: rc=$G_RC out=$G_OUT"; fi
fresh_case b1a5s
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-B1A5S CH-B1A5S 1 GO "$NONE" D-B1A5S
rr_ledger_row D-B1A5S sonnet xhigh
gate CH-B1A5S
if uncovered CH-B1A5S; then ok "B1-A5b: ledger label model 'sonnet' -> UNCOVERED"
else bad "B1-A5b: rc=$G_RC out=$G_OUT"; fi

# --- B1 probe A6: producer == reviewer ------------------------------------
fresh_case b1a6
RR_PRODUCER=D-SAME rr_genuine "$REC/r1.json" B-B1A6 CH-B1A6 1 GO "$NONE" D-SAME
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r1.json" ] && grep -q "certify its own work" "$RR_WORK/r1/record.err"; then ok "B1-A6: record refuses (rc 1, nothing written) when --producer-id equals the reviewer dispatch id"
else bad "B1-A6: rc=$RR_RC exists=$([ -f "$REC/r1.json" ] && echo y || echo n)"; fi
fresh_case b1a6b
RR_PRODUCER='' rr_genuine "$REC/r1.json" B-B1A6B CH-B1A6B 1 GO "$NONE" D-B1A6B
gate CH-B1A6B
if uncovered CH-B1A6B && printf '%s\n' "$G_OUT" | grep -q "producer"; then ok "B1-A6b: a record with no producer identity never qualifies"
else bad "B1-A6b: rc_record=$RR_RC rc=$G_RC out=$G_OUT"; fi

# --- B1 probe B: genuine round-1 NO-GO, producer forges a round-2 GO reusing the reviewer's dispatch
fresh_case b1b
rr_genuine "$REC/r1.json" B-B1B CH-B1B 1 NO-GO '[{"id":"F1","severity":"BLOCKING","finding_layer":"source-defect"}]' D-B1B
gate CH-B1B; R1RC=$G_RC
RR_SKIP_LEDGER=1 rr_genuine "$REC/r2.json" B-B1B CH-B1B 2 GO "$NONE" D-B1B
gate CH-B1B
if [ "$R1RC" -eq 1 ] && uncovered CH-B1B && printf '%s\n' "$G_OUT" | grep -q "reused"; then
  ok "B1-B: a round-2 GO reusing the round-1 reviewer's dispatch id is refused (one dispatch backs one verdict)"
else bad "B1-B: r1rc=$R1RC rc=$G_RC out=$G_OUT"; fi

# --- B1 probe C: record edited after writing ------------------------------
fresh_case b1c
rr_genuine "$REC/r1.json" B-B1C CH-B1C 1 NO-GO "$NONE" D-B1C
python3 - "$REC/r1.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["verdict"] = "GO"; json.dump(d, open(p, "w"))
PY
gate CH-B1C; RC_A=$G_RC; OUT_A=$G_OUT
python3 - "$REC/r1.json" <<'PY'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p))
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
gate CH-B1C
if [ "$RC_A" -eq 1 ] && printf '%s\n' "$OUT_A" | grep -q "body_hash" && uncovered CH-B1C && printf '%s\n' "$G_OUT" | grep -q "evidence"; then
  ok "B1-C: an edited record is refused (body_hash), and an edited record with a re-computed body_hash is still refused (verdict re-derived from the reviewer's archived evidence)"
else bad "B1-C: rcA=$RC_A outA=$OUT_A rc=$G_RC out=$G_OUT"; fi

# --- B1 probe D: high-blast seams need capability independence -------------
fresh_case b1d
rr_genuine "$REC/r1.json" B-B1D CH-B1D 1 GO "$NONE" D-B1D
for seam in release-tag qa-deploy manual-qa-handoff; do
  gate CH-B1D --seam "$seam"
  if uncovered CH-B1D && printf '%s\n' "$G_OUT" | grep -q "capability"; then ok "B1-D: seam $seam refuses an instance-tier verdict (11.4.240(F)(4))"
  else bad "B1-D $seam: rc=$G_RC out=$G_OUT"; fi
done
gate CH-B1D --seam bogus-seam
if [ "$G_RC" -eq 2 ]; then ok "B1-D2: unknown --seam value is a usage error (2), never a silent ordinary seam"
else bad "B1-D2: rc=$G_RC out=$G_OUT"; fi

# capability tier: only producible on a host with a genuine uid boundary.
# The real module's main() runs in-process with os.geteuid substituted and
# every evidence path made read-only, so the owner and writability checks are
# both genuinely exercised. Skipped honestly when running as root (root can
# write anything, so os.access cannot prove a boundary).
if [ "$(id -u)" -ne 0 ]; then
  chmod -R a-w "$REC" "$RR_LEDGER"; chmod a-w "$CASE"
  CAP_OUT=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" <<'PY'
import importlib.util, io, os, sys, contextlib
tool, rec, ledger = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("rr", tool)
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
real = os.geteuid()
os.geteuid = lambda: real + 1
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = rr.main(["gate", "--change", "CH-B1D", "--records", rec, "--dispatch-ledger", ledger, "--seam", "release-tag"])
print("RC=%s %s" % (rc, buf.getvalue().strip()))
PY
)
  chmod u+w "$CASE" "$RR_LEDGER"; chmod -R u+w "$REC"
  if printf '%s\n' "$CAP_OUT" | grep -q "^RC=0 COVERED CH-B1D .*independence=capability"; then
    ok "B1-D3: foreign-owned, non-writable evidence achieves 'capability' and passes the release-tag seam"
  else bad "B1-D3: $CAP_OUT"; fi
  # Same but the records dir left writable: the boundary is not real -> instance.
  CAP_OUT=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" <<'PY'
import importlib.util, io, os, sys, contextlib
tool, rec, ledger = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("rr", tool)
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
real = os.geteuid()
os.geteuid = lambda: real + 1
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = rr.main(["gate", "--change", "CH-B1D", "--records", rec, "--dispatch-ledger", ledger, "--seam", "release-tag"])
print("RC=%s %s" % (rc, buf.getvalue().strip()))
PY
)
  if printf '%s\n' "$CAP_OUT" | grep -q "^RC=1 UNCOVERED CH-B1D"; then
    ok "B1-D4: foreign owner but WRITABLE evidence is only 'instance' -> release-tag still refused"
  else bad "B1-D4: $CAP_OUT"; fi
else
  echo "NOTE: running as root -- B1-D3/B1-D4 capability checks SKIPPED (os.access cannot prove a uid boundary for root)"
fi

# --- B1 probe D5: same-owner read-only evidence is still only 'instance' ---
# (no geteuid substitution: the real owner check must refuse capability for
# files this uid owns, even when they are made read-only -- an owner can
# always chmod them back).
if [ "$(id -u)" -ne 0 ]; then
  fresh_case b1d5
  rr_genuine "$REC/r1.json" B-B1D5 CH-B1D5 1 GO "$NONE" D-B1D5
  chmod -R a-w "$REC" "$RR_LEDGER"; chmod a-w "$CASE"
  gate CH-B1D5 --seam release-tag
  chmod u+w "$CASE" "$RR_LEDGER"; chmod -R u+w "$REC"
  if uncovered CH-B1D5 && printf '%s\n' "$G_OUT" | grep -q "achieved instance"; then
    ok "B1-D5: read-only evidence OWNED by this uid is only 'instance' -> release-tag refused"
  else bad "B1-D5: rc=$G_RC out=$G_OUT"; fi
fi

# --- B1 probe E: record round edited (re-hashed) away from the evidence ----
fresh_case b1e
rr_genuine "$REC/r1.json" B-B1E CH-B1E 1 GO "$NONE" D-B1E
python3 - "$REC/r1.json" <<'PY2'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p)); d["round"] = 2
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY2
gate CH-B1E
if uncovered CH-B1E && printf '%s\n' "$G_OUT" | grep -q "evidence round"; then
  ok "B1-E: a record whose round was edited away from the reviewer's archived round is refused"
else bad "B1-E: rc=$G_RC out=$G_OUT"; fi

# --- B1 probe G: reviewer self-report disagrees with --tier/--effort -------
fresh_case b1g
RR_REVIEWER_MODEL=sonnet rr_genuine "$REC/r1.json" B-B1G CH-B1G 1 GO "$NONE" D-B1G
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r1.json" ] && grep -q "disagrees" "$RR_WORK/r1/record.err"; then
  ok "B1-G: record refuses (rc 1) when the reviewer's own model/effort disagrees with --tier/--effort"
else bad "B1-G: rc=$RR_RC err=$(cat "$RR_WORK/r1/record.err")"; fi

# --- B1 probe H: honest '?' effort (capability gap) is recorded, never coverage
fresh_case b1h
RR_SKIP_LEDGER=1 RR_REVIEWER_EFFORT='?' rr_genuine "$REC/r1.json" B-B1H CH-B1H 1 GO "$NONE" D-B1H --effort '?'
rr_ledger_row D-B1H opus '?'
gate CH-B1H
if [ "$RR_RC" -eq 0 ] && uncovered CH-B1H && printf '%s\n' "$G_OUT" | grep -q "tier/effort"; then
  ok "B1-H: a genuine, consistent '?'-effort review (honest capability gap) is recorded but never coverage (RB-004)"
else bad "B1-H: rc_record=$RR_RC err=$(cat "$RR_WORK/r1/record.err") rc=$G_RC out=$G_OUT"; fi

# --- B2 M1: GO that still carries a finding --------------------------------
fresh_case m1
rr_genuine "$REC/r1.json" B-M1 CH-M1 1 GO '[{"id":"F1","severity":"NIT","finding_layer":"process-doc"}]' D-M1
gate CH-M1
if [ "$RR_RC" -eq 0 ] && uncovered CH-M1; then ok "B2-M1: a reviewer GO carrying a finding is not coverage (zero-finding rule)"
else bad "B2-M1: rc_record=$RR_RC rc=$G_RC out=$G_OUT"; fi

# --- B2 M2/M3: NO-GO with zero findings ------------------------------------
fresh_case m2
rr_genuine "$REC/r1.json" B-M2 CH-M2 1 NO-GO "$NONE" D-M2
gate CH-M2
V=$(field "$REC/r1.json" verdict)
if [ "$V" = '"NO-GO"' ]; then ok "B2-M3: a zero-finding NO-GO is recorded verbatim as NO-GO (never rewritten to GO)"
else bad "B2-M3: recorded verdict=$V"; fi
if uncovered CH-M2; then ok "B2-M2: a zero-finding NO-GO is not coverage (verdict==GO rule)"
else bad "B2-M2: rc=$G_RC out=$G_OUT"; fi

# --- B2 M4: latest round wins ---------------------------------------------
fresh_case m4
rr_genuine "$REC/r1.json" B-M4 CH-M4 1 GO "$NONE" D-M4A
rr_genuine "$REC/r2.json" B-M4 CH-M4 2 NO-GO '[{"id":"F9","severity":"IMPORTANT","finding_layer":"source-defect"}]' D-M4B
gate CH-M4
if uncovered CH-M4; then ok "B2-M4: round-1 GO superseded by round-2 NO-GO -> UNCOVERED (latest round decides)"
else bad "B2-M4: rc=$G_RC out=$G_OUT"; fi
fresh_case m4n
rr_genuine "$REC/r1.json" B-M4N CH-M4N 1 NO-GO '[{"id":"F9","severity":"IMPORTANT","finding_layer":"source-defect"}]' D-M4NA
rr_genuine "$REC/r2.json" B-M4N CH-M4N 2 GO "$NONE" D-M4NB
gate CH-M4N
if covered CH-M4N && printf '%s\n' "$G_OUT" | grep -q "round=2"; then ok "B2-M4n (negative control): round-1 NO-GO superseded by a genuine round-2 GO -> COVERED round=2"
else bad "B2-M4n: rc=$G_RC out=$G_OUT"; fi

# --- B2 M5 (reviewer, already killed elsewhere): source-defect stays source-defect
V=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["findings"][0].get("finding_layer"))' "$CASE/records/r1.json")
if [ "$V" = "source-defect" ]; then ok "B2-M5: finding_layer source-defect recorded verbatim (never lowered)"
else bad "B2-M5: got $V"; fi

# --- I1: same-round conflict ------------------------------------------------
fresh_case i1
rr_genuine "$REC/a_producer.json" B-I1 CH-I1 1 GO "$NONE" D-I1A
rr_genuine "$REC/z_reviewer.json" B-I1 CH-I1 1 NO-GO '[{"id":"F1","severity":"BLOCKING","finding_layer":"source-defect"}]' D-I1B
gate CH-I1; RC_A=$G_RC; OUT_A=$G_OUT
mv "$REC/a_producer.json" "$REC/zz_producer.json"
gate CH-I1
if [ "$RC_A" -eq 4 ] && [ "$G_RC" -eq 4 ] && printf '%s\n' "$OUT_A" | grep -q "conflict"; then
  ok "I1: two different records for the same batch+round are refused (rc 4) regardless of filename order"
else bad "I1: rcA=$RC_A outA=$OUT_A rcB=$G_RC outB=$G_OUT"; fi
fresh_case i1n
rr_genuine "$REC/r1.json" B-I1N CH-I1N 1 GO "$NONE" D-I1N
cp "$REC/r1.json" "$REC/r1_copy.json"
gate CH-I1N
if covered CH-I1N; then ok "I1n (negative control): a byte-identical duplicate record is not a conflict"
else bad "I1n: rc=$G_RC out=$G_OUT"; fi

# --- I2: evidence resolved against the record's own directory --------------
fresh_case i2
mkdir -p "$REC/sub/rec2/deep"
rr_genuine "$REC/sub/rec2/deep/r1.json" B-I2 CH-I2 1 GO "$NONE" D-I2
G_OUT=$(python3 "$RR_TOOL" gate --change CH-I2 --records "$REC/sub/rec2" --dispatch-ledger "$RR_LEDGER" 2>&1); RC_A=$?; OUT_A=$G_OUT
G_OUT=$(python3 "$RR_TOOL" gate --change CH-I2 --records "$REC/sub/rec2/deep" --dispatch-ledger "$RR_LEDGER" 2>&1); G_RC=$?
if [ "$RC_A" -eq 0 ] && covered CH-I2; then ok "I2: a nested genuine record is COVERED both from an ancestor --records and from its own directory"
else bad "I2: ancestor rc=$RC_A out=$OUT_A own rc=$G_RC out=$G_OUT"; fi

# --- I3a: round budget ------------------------------------------------------
fresh_case i3
rr_genuine "$REC/r6.json" B-I3 CH-I3 6 GO "$NONE" D-I3A
if [ "$RR_RC" -eq 1 ] && [ ! -f "$REC/r6.json" ] && grep -q "review-round budget" "$RR_WORK/r6/record.err"; then ok "I3a: record refuses round 6 under the default 11.4.276 budget of 5 (rc 1, nothing written)"
else bad "I3a: rc=$RR_RC"; fi
rr_genuine "$REC/r42.json" B-I3 CH-I3 42 GO "$NONE" D-I3B --round-budget 7
if [ "$RR_RC" -eq 1 ]; then ok "I3a2: round 42 refused even under the maximum budget 7"
else bad "I3a2: rc=$RR_RC"; fi
rr_genuine "$REC/r6b.json" B-I3 CH-I3 6 GO "$NONE" D-I3C --round-budget 9
if [ "$RR_RC" -eq 2 ] && grep -q "round-budget must be within" "$RR_WORK/r6b/record.err"; then ok "I3a3: --round-budget outside 5..7 is a usage error (2)"
else bad "I3a3: rc=$RR_RC"; fi
rr_genuine "$REC/r6c.json" B-I3 CH-I3 6 GO "$NONE" D-I3D --round-budget 7
gate CH-I3; RC_A=$G_RC; OUT_A=$G_OUT
gate CH-I3 --round-budget 7
if [ "$RR_RC" -eq 0 ] && [ "$RC_A" -eq 1 ] && printf '%s\n' "$OUT_A" | grep -q "budget" && covered CH-I3; then
  ok "I3a4: a round-6 record (budget 7) is UNCOVERED under the gate's default budget 5 and COVERED under --round-budget 7"
else bad "I3a4: rc_record=$RR_RC rcA=$RC_A outA=$OUT_A rc=$G_RC out=$G_OUT"; fi

# --- I3b: per-slice verdicts (11.4.235(D)) ---------------------------------
TWO='[{"slice_id":"S1","lines":3},{"slice_id":"S2","lines":4}]'
fresh_case i3b
RR_SLICES="$TWO" rr_genuine "$REC/r1.json" B-I3B CH-I3B 1 GO "$NONE" D-I3B1
gate CH-I3B
if uncovered CH-I3B && printf '%s\n' "$G_OUT" | grep -q "slice"; then ok "I3b: a multi-slice batch with no per-slice verdicts is not coverage"
else bad "I3b: rc_record=$RR_RC rc=$G_RC out=$G_OUT"; fi
fresh_case i3b2
RR_SLICES="$TWO" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S2","verdict":"GO"}]' \
  rr_genuine "$REC/r1.json" B-I3B2 CH-I3B2 1 GO "$NONE" D-I3B2
gate CH-I3B2
if covered CH-I3B2; then ok "I3b2 (negative control): every slice GO -> COVERED"
else bad "I3b2: rc_record=$RR_RC err=$(cat "$RR_WORK/r1/record.err") rc=$G_RC out=$G_OUT"; fi
fresh_case i3b3
RR_SLICES="$TWO" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S9","verdict":"GO"}]' \
  rr_genuine "$REC/r1.json" B-I3B3 CH-I3B3 1 GO "$NONE" D-I3B3
if [ "$RR_RC" -eq 2 ] && grep -q "unknown slice" "$RR_WORK/r1/record.err"; then ok "I3b3: a slice verdict naming an unknown slice is a usage error (2)"
else bad "I3b3: rc=$RR_RC"; fi
RR_SLICES="$TWO" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S2","verdict":"NO-GO"}]' \
  rr_genuine "$REC/r1b.json" B-I3B3 CH-I3B3 1 GO "$NONE" D-I3B4
if [ "$RR_RC" -eq 2 ] && grep -q "contradicts a NO-GO slice" "$RR_WORK/r1b/record.err"; then ok "I3b4: overall GO contradicting a NO-GO slice is refused (2)"
else bad "I3b4: rc=$RR_RC"; fi
RR_SLICES="$TWO" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S2","verdict":"NO-GO"}]' \
  rr_genuine "$REC/r1c.json" B-I3B3 CH-I3B3 1 NO-GO '[{"id":"F1","severity":"MINOR","slice_id":"S1","finding_layer":"source-defect"}]' D-I3B5
if [ "$RR_RC" -eq 2 ] && grep -q "is GO but holds finding" "$RR_WORK/r1c/record.err"; then ok "I3b5: a GO slice holding an open source-defect finding is refused (11.4.235(D))"
else bad "I3b5: rc=$RR_RC"; fi
RR_SLICES="$TWO" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S2","verdict":"NO-GO"}]' \
  rr_genuine "$REC/r1d.json" B-I3B3 CH-I3B3 1 NO-GO '[{"id":"F1","severity":"MINOR","slice_id":"S1"}]' D-I3B6
if [ "$RR_RC" -eq 2 ] && grep -q "defaults to source-defect" "$RR_WORK/r1d/record.err"; then ok "I3b6: an unclassified finding on a GO slice defaults to source-defect and is refused (11.4.235(D) conservative default)"
else bad "I3b6: rc=$RR_RC"; fi
RR_SLICES="$TWO" RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S2","verdict":"NO-GO"}]' \
  rr_genuine "$REC/r1e.json" B-I3B3 CH-I3B3 1 NO-GO '[{"id":"F1","severity":"MINOR","slice_id":"S1","finding_layer":"test-instrumentation"}]' D-I3B7
if [ "$RR_RC" -eq 0 ]; then ok "I3b7 (negative control): a GO slice whose only finding is test-instrumentation is accepted (11.4.235(D) build-eligible)"
else bad "I3b7: rc=$RR_RC err=$(cat "$RR_WORK/r1e/record.err")"; fi

# --- M-a: boolean round in the verdict file --------------------------------
fresh_case ma
python3 - "$RR_WORK" <<'PY'
import json, os, sys
d = os.path.join(sys.argv[1], "ma"); os.makedirs(d, exist_ok=True)
json.dump({"batch_id": "B-MA", "changes": ["CH-MA"]}, open(os.path.join(d, "batch.json"), "w"))
json.dump({"round": True, "verdict": "GO", "findings": []}, open(os.path.join(d, "verdict.json"), "w"))
PY
python3 "$RR_TOOL" record --batch "$RR_WORK/ma/batch.json" --round 1 --verdict-file "$RR_WORK/ma/verdict.json" \
  --tier opus --effort xhigh --out "$REC/ma.json" >/dev/null 2>"$CASE/ma.err"
RC=$?
if [ "$RC" -eq 2 ] && [ ! -f "$REC/ma.json" ] && grep -q "must be an integer" "$CASE/ma.err"; then ok "M-a: verdict-file round=true is refused (2), never read as round 1"
else bad "M-a: rc=$RC"; fi

# --- backfill rows record history, never coverage ---------------------------
fresh_case bf
echo "# genuine historical notes" > "$REC/notes.md"
cat > "$CASE/bf.json" <<'EOF'
{"review_id":"R-BF","batch_id":"B-BF","round":1,"verdict":"GO","source_evidence":"notes.md",
 "model_tier":"opus","effort":"xhigh","change_ids":["CH-BF"],"findings":[]}
EOF
python3 "$RR_TOOL" backfill --input "$CASE/bf.json" --out "$REC/bf.json" >/dev/null 2>&1
gate CH-BF
if uncovered CH-BF && printf '%s\n' "$G_OUT" | grep -q "backfill"; then ok "BF: a well-cited backfill row is history only -- never gate coverage"
else bad "BF: rc=$G_RC out=$G_OUT"; fi

# a GENUINE live record relabelled source=backfill (body re-hashed, all live
# evidence intact) is still not coverage: backfill is history by source.
fresh_case bf2
rr_genuine "$REC/r1.json" B-BF2 CH-BF2 1 GO "$NONE" D-BF2
python3 - "$REC/r1.json" <<'PY2'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p)); d["source"] = "backfill"
body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY2
gate CH-BF2
if uncovered CH-BF2; then ok "BF2: a genuine live record relabelled source=backfill is not coverage, even with intact live evidence"
else bad "BF2: rc=$G_RC out=$G_OUT"; fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
